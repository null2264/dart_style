// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:path/path.dart' as p;

// Aside from not needing `break;`, this is all just using enhanced enums and
// not pattern matching.

/// Which file paths should be printed.
enum Show {
  /// No files.
  none,

  /// All traversed files.
  all,

  /// Only files whose formatting changed.
  changed,

  /// The legacy dartfmt output style when not overwriting files.
  legacy,

  /// The legacy dartfmt output style when overwriting files.
  overwrite,

  /// The legacy dartfmt output style in "--dry-run".
  dryRun;

  /// The display path to show for [file] which is in [directory].
  ///
  /// In the old CLI, this does not include [directory], since the directory
  /// name is printed separately. The new CLI only prints file paths, so this
  /// includes the root directory to disambiguate which directory the file is
  /// in.
  String displayPath(String directory, String file) {
    switch (this) {
      case Show.dryRun | Show.legacy | Show.overwrite:
        return p.relative(file, from: directory);
      default:
        return p.normalize(file);
    }
  }

  /// Describes a file that was processed.
  ///
  /// Returns whether or not this file should be displayed.
  bool file(String path, {required bool changed, required bool overwritten}) {
    switch (this) {
      case Show.all | Show.overwrite:
        if (changed) {
          _showFileChange(path, overwritten: overwritten);
        } else {
          print('Unchanged $path');
        }

        return true;

      case Show.changed:
        if (changed) _showFileChange(path, overwritten: overwritten);
        return changed;

      case Show.dryRun:
        if (changed) print(path);
        return true;

      default:
        return true;
    }
  }

  /// Describes the directory whose contents are about to be processed.
  void directory(String path) {
    switch (this) {
      case Show.legacy | Show.overwrite:
        print('Formatting directory $directory:');
      default:
        // Do nothing.
    }
  }

  /// Describes the symlink at [path] that wasn't followed.
  void skippedLink(String path) {
    switch (this) {
      case Show.legacy | Show.overwrite:
        print('Skipping link $path');
      default:
        // Do nothing.
    }
  }

  /// Describes the hidden [path] that wasn't processed.
  void hiddenPath(String path) {
    switch (this) {
      case Show.legacy | Show.overwrite:
        print('Skipping hidden path $path');
      default:
        // Do nothing.
    }
  }

  void _showFileChange(String path, {required bool overwritten}) {
    if (overwritten) {
      print('Formatted $path');
    } else {
      print('Changed $path');
    }
  }
}
