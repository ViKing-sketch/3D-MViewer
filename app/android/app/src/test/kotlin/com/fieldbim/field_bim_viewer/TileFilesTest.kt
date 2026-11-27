package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class TileFilesTest {
    @Test
    fun aNullAllowKeepsEveryFile() {
        val files = listOf(File("1.glb"), File("2.glb"), File("notes.txt"))
        assertEquals(files, TileFiles.matching(files, null))
    }

    @Test
    fun aTileKeepsOnlyItsElementFiles() {
        val files = listOf(File("1.glb"), File("2.glb"), File("30.glb"), File("x.glb"))
        val kept = TileFiles.matching(files, setOf(2L, 30L))
        assertEquals(listOf(File("2.glb"), File("30.glb")), kept)
    }

    @Test
    fun anEmptyTileDoesNotKeepTheRest() {
        val files = listOf(File("1.glb"), File("2.glb"))
        assertEquals(emptyList<File>(), TileFiles.matching(files, emptySet()))
    }
}
