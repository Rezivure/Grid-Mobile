/// True only for flutter_rust_bridge's duplicate-init error.
///
/// The bridge throws `Should not initialize flutter_rust_bridge twice` when
/// its state is already non-null, so a previous init succeeded. A
/// codegen/runtime version mismatch also mentions `flutter_rust_bridge`, but
/// only inside its documentation URL, and that init did not succeed.
bool isDuplicateVodInitError(Object error) {
  return error.toString().contains(
        'Should not initialize flutter_rust_bridge twice',
      );
}
