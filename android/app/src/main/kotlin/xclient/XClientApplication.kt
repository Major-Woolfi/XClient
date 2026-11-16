package com.xclient

import android.app.Application
import android.content.Context
import com.xclient.common.GlobalState

class XClientApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}


