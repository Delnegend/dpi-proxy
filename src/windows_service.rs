//! Windows Service Control Manager integration.

use std::error::Error;
use std::ffi::{c_ulong, c_void};
use std::io;
use std::ptr::{null, null_mut};
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;
use tokio::sync::oneshot;
use windows_sys::Win32::Foundation::GetLastError;
use windows_sys::Win32::System::Services::{
    RegisterServiceCtrlHandlerExA, SERVICE_CONTROL_SHUTDOWN, SERVICE_CONTROL_STOP, SERVICE_RUNNING,
    SERVICE_START_PENDING, SERVICE_STATUS, SERVICE_STATUS_HANDLE, SERVICE_STOP_PENDING,
    SERVICE_STOPPED, SERVICE_TABLE_ENTRYA, SERVICE_WIN32_OWN_PROCESS, SetServiceStatus,
    StartServiceCtrlDispatcherA,
};

use crate::{load_config, proxy};

static SERVICE_NAME: &[u8] = b"DpiProxy\0";
static SERVICE_STATUS_HANDLE_VAL: AtomicPtr<c_void> = AtomicPtr::new(null_mut());
static SHUTDOWN_TX: Mutex<Option<oneshot::Sender<()>>> = Mutex::new(None);

pub(crate) fn run() -> Result<bool, Box<dyn Error>> {
    let service_table = [
        SERVICE_TABLE_ENTRYA {
            lpServiceName: SERVICE_NAME.as_ptr().cast_mut(),
            lpServiceProc: Some(service_main),
        },
        SERVICE_TABLE_ENTRYA {
            lpServiceName: null_mut(),
            lpServiceProc: None,
        },
    ];

    let ok = unsafe { StartServiceCtrlDispatcherA(service_table.as_ptr()) };
    if ok == 0 {
        let err = unsafe { GetLastError() };
        // 1063 = ERROR_FAILED_SERVICE_CONTROLLER_CONNECT
        // This indicates the process was run interactively from console, not by SCM.
        if err == 1063 {
            return Ok(false);
        }
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Failed to start service control dispatcher (error code {err})"),
        )
        .into());
    }

    Ok(true)
}

unsafe extern "system" fn service_handler(
    dw_control: u32,
    _dw_event_type: u32,
    _lp_event_data: *mut c_void,
    _lp_context: *mut c_void,
) -> u32 {
    match dw_control {
        SERVICE_CONTROL_STOP | SERVICE_CONTROL_SHUTDOWN => {
            let handle = SERVICE_STATUS_HANDLE_VAL.load(Ordering::Relaxed);
            if !handle.is_null() {
                let status = SERVICE_STATUS {
                    dwServiceType: SERVICE_WIN32_OWN_PROCESS,
                    dwCurrentState: SERVICE_STOP_PENDING,
                    dwControlsAccepted: 0,
                    dwWin32ExitCode: 0,
                    dwServiceSpecificExitCode: 0,
                    dwCheckPoint: 1,
                    dwWaitHint: 3000,
                };
                unsafe {
                    SetServiceStatus(handle.cast(), &status);
                }
            }
            if let Ok(mut lock) = SHUTDOWN_TX.lock() {
                if let Some(tx) = lock.take() {
                    let _ = tx.send(());
                }
            }
            0
        }
        _ => 120, // ERROR_CALL_NOT_IMPLEMENTED
    }
}

unsafe extern "system" fn service_main(
    _dw_num_service_args: c_ulong,
    _lp_service_arg_vectors: *mut *mut u8,
) {
    let handle: SERVICE_STATUS_HANDLE = unsafe {
        RegisterServiceCtrlHandlerExA(SERVICE_NAME.as_ptr(), Some(service_handler), null_mut())
    };
    if handle.is_null() {
        return;
    }
    SERVICE_STATUS_HANDLE_VAL.store(handle.cast(), Ordering::Relaxed);

    let mut status = SERVICE_STATUS {
        dwServiceType: SERVICE_WIN32_OWN_PROCESS,
        dwCurrentState: SERVICE_START_PENDING,
        dwControlsAccepted: SERVICE_CONTROL_STOP | SERVICE_CONTROL_SHUTDOWN,
        dwWin32ExitCode: 0,
        dwServiceSpecificExitCode: 0,
        dwCheckPoint: 0,
        dwWaitHint: 3000,
    };
    unsafe {
        SetServiceStatus(handle, &status);
    }

    let (tx, rx) = oneshot::channel();
    if let Ok(mut lock) = SHUTDOWN_TX.lock() {
        *lock = Some(tx);
    }

    let rt = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(_) => {
            status.dwCurrentState = SERVICE_STOPPED;
            unsafe {
                SetServiceStatus(handle, &status);
            }
            return;
        }
    };

    rt.block_on(async {
        let options = match load_config() {
            Ok(opts) => opts,
            Err(_) => return,
        };
        let listener = match TcpListener::bind((options.address.as_str(), options.port)).await {
            Ok(l) => l,
            Err(_) => return,
        };

        status.dwCurrentState = SERVICE_RUNNING;
        unsafe {
            SetServiceStatus(handle, &status);
        }

        tokio::select! {
            _ = proxy::serve(listener, Arc::new(options.bypass)) => {}
            _ = rx => {}
        }
    });

    status.dwCurrentState = SERVICE_STOPPED;
    unsafe {
        SetServiceStatus(handle, &status);
    }
}
