package com.fieldbim.field_bim_viewer

import java.io.File

/**
 * Element GLBs that belong to the tile being streamed.
 *
 * A null [allow] is a package with no tile index: every element file stays.
 * A set, including an empty one, never falls back to the rest of the model.
 * The file name is `<elementId>.glb`.
 */
object TileFiles {
    fun matching(files: List<File>, allow: Set<Long>?): List<File> {
        if (allow == null) return files
        return files.filter { file ->
            val name = file.name
            if (!name.endsWith(".glb")) return@filter false
            val id = name.removeSuffix(".glb").toLongOrNull() ?: return@filter false
            id in allow
        }
    }
}
