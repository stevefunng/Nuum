package com.nuum.feature.shell

import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.SidebarSection
import com.nuum.feature.shell.sidebar.prepareSidebarSave
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.SIDEBAR_UNIQUENESS_MESSAGE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SidebarSaveTest {
    @Test
    fun duplicateTrimmedGroupNameUsesTheProtocolSentence() {
        val organization = SidebarOrganization(
            sections = listOf(
                SidebarSection("g1", "Design", emptyList()),
                SidebarSection("g2", "  Design  ", emptyList())
            )
        )
        val error = assertThrows(ProtocolParseException::class.java) {
            prepareSidebarSave(organization)
        }
        assertEquals(SIDEBAR_UNIQUENESS_MESSAGE, error.issues.single().message)
    }
}
