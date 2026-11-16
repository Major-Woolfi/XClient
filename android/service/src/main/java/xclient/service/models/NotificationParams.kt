package com.xclient.service.models

data class NotificationParams(
    val title: String = "XClient",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)


