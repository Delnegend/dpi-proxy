function FindProxyForURL(url, host) {
    // Domains required for Steam Store, Community, Friends, and Game Downloads
    var steamDomains = [
        "steampowered.com",
        "steamcommunity.com",
        "steamgames.com",
        "steamusercontent.com",
        "steamcontent.com",
        "steamstatic.com",
        "steamserver.net",
        "steam-chat.com",
        "akamaihd.net",
        "akamaized.net",
        "valvesoftware.com",
        "valve.net",
        "dota2.com",
        "steamdeck.com",
        "s.team",
        "steam.tv"
    ];

    for (var i = 0; i < steamDomains.length; i++) {
        var domain = steamDomains[i];
        if (host === domain || dnsDomainIs(host, "." + domain)) {
            // Homebrew service defaults to 18118; change to 1080 for manual/container launches
            return "PROXY 127.0.0.1:18118; DIRECT";
        }
    }

    return "DIRECT";
}
