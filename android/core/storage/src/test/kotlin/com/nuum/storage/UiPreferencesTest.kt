package com.nuum.storage

import kotlinx.coroutines.flow.first
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UiPreferencesTest : StorageRobolectricTest() {
    @Test
    fun sidebarWidthAndIdentityEditedRoundTrip() = withStore { store ->
        assertEquals(
            SidebarLayout(SidebarLayoutLimits.DEFAULT_EXPANDED_WIDTH, false),
            store.readSidebarLayout()
        )
        assertFalse(store.hasEditedIdentity("a1"))

        store.writeSidebarLayout(SidebarLayout(300, true))
        assertEquals(SidebarLayout(300, true), store.readSidebarLayout())

        store.writeSidebarLayout(SidebarLayout(10, false))
        assertEquals(SidebarLayoutLimits.MIN_EXPANDED_WIDTH, store.readSidebarLayout().expandedWidth)
        assertFalse(store.readSidebarLayout().isCollapsed)

        store.writeSidebarLayout(SidebarLayout(900, false))
        assertEquals(SidebarLayoutLimits.MAX_EXPANDED_WIDTH, store.readSidebarLayout().expandedWidth)

        store.markIdentityEdited("a1")
        store.markIdentityEdited("a1")
        assertTrue(store.hasEditedIdentity("a1"))
        assertFalse(store.hasEditedIdentity("a2"))
        assertEquals(setOf("a1"), store.identityEdited.first())
    }
}
