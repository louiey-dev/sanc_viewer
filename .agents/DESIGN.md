# DESIGN

Simple UI with menu tab, light weight app and fast run with small resources.

## Purpose

This app is image viewer with screen capture function.
Support jpg/png/ico and so on, all image files.
Simple UI with display file/image detail informations, pixel/size/format/time/geo and so on.
Display next/prev images.
Capture function included with window/manual area selection.
Left side, display folder info and files and this tab is foldable.

## State and lifecycle

Riverpod and go router is basic package.
There should be no pixel overflow error at UI.

## Conventions

- Use relative imports for easy copying.
- Use `m.log/dbg/err` instead of direct `print` calls. (my_utils.dart)
- Add Dartdoc comments to public methods and reusable APIs.
