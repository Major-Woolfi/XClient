package com.xclient.models

import com.xclient.service.models.VpnOptions
import com.google.gson.JsonObject

data class SharedState(
    val startTip: String = "Starting VPN...",
    val stopTip: String = "Stopping VPN...",
    val localNetworkTip: String =
        "Local network permission denied: using the gvisor stack, LAN is unreachable.",
    val currentProfileName: String = "XClient",
    val stopText: String = "Stop",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
    val vpnOptions: VpnOptions? = null,
    // The Core's own setup params, handed on as Flutter wrote them.
    val setupParams: JsonObject? = null,
)


