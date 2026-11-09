function FindProxyForURL(url, host) {
    // Normalize IPv6 address brackets if present (e.g. "[::1]" -> "::1")
    var cleanHost = host;
    if (cleanHost.length > 2 && cleanHost.charAt(0) === "[" && cleanHost.charAt(cleanHost.length - 1) === "]") {
        cleanHost = cleanHost.substring(1, cleanHost.length - 1);
    }

    // 1. Localhost, plain hostnames (no dots), local domains, and Tailscale MagicDNS
    if (
        isPlainHostName(cleanHost) ||
        cleanHost === "localhost" ||
        shExpMatch(cleanHost, "*.localhost") ||
        shExpMatch(cleanHost, "*.local") ||
        shExpMatch(cleanHost, "*.internal") ||
        shExpMatch(cleanHost, "*.ts.net") ||
        cleanHost === "127.0.0.1" ||
        cleanHost === "::1"
    ) {
        return "DIRECT";
    }

    // 2. IPv6 link-local and unique local addresses (including Tailscale IPv6)
    if (
        shExpMatch(cleanHost, "fe80:*") ||
        shExpMatch(cleanHost, "fc*:*") ||
        shExpMatch(cleanHost, "fd*:*")
    ) {
        return "DIRECT";
    }

    // 3. Resolve host to IPv4 or check IPv4 literal against blacklisted CIDRs
    var resolved_ip = dnsResolve(cleanHost);
    var is_ipv4 = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(cleanHost);
    var ip = resolved_ip || (is_ipv4 ? cleanHost : null);

    if (ip) {
        if (
            // Loopback: 127.0.0.0/8
            isInNet(ip, "127.0.0.0", "255.0.0.0") ||
            // RFC 1918 Private networks
            isInNet(ip, "10.0.0.0", "255.0.0.0") ||
            isInNet(ip, "172.16.0.0", "255.240.0.0") ||
            isInNet(ip, "192.168.0.0", "255.255.0.0") ||
            // Link-Local (APIPA): 169.254.0.0/16
            isInNet(ip, "169.254.0.0", "255.255.0.0") ||
            // Tailscale / Carrier-Grade NAT (RFC 6598): 100.64.0.0/10
            isInNet(ip, "100.64.0.0", "255.192.0.0") ||
            // Current network / Multicast / Reserved
            isInNet(ip, "0.0.0.0", "255.0.0.0") ||
            isInNet(ip, "224.0.0.0", "240.0.0.0") ||
            isInNet(ip, "240.0.0.0", "240.0.0.0")
        ) {
            return "DIRECT";
        }
    }

    // Route all other traffic through dpi-proxy (port 18118) with DIRECT fallback
    return "PROXY 127.0.0.1:18118; DIRECT";
}
