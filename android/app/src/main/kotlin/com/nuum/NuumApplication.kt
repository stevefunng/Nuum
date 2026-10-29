package com.nuum

import android.app.Application

/**
 * Process entry. Object graph wiring stays out of this class until WP-12.
 * `app/.../graph/` is intentionally absent.
 */
class NuumApplication : Application()
