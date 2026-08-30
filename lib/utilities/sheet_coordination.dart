/// Pure geometry helpers for coordinating the two stacked bottom sheets
/// on the map screen (#305 "double menu overlay obstructs map").
///
/// MapTab renders a persistent list sheet (contacts/groups) *and*, when a
/// contact is tapped, an inline contact-profile sheet on top of it. If the
/// list sheet is left expanded, the two menus stack and hide the map. When
/// an overlay sheet is present we collapse the background list sheet down to
/// its minimum so only one menu is showing over the map.
library;

/// Target extent the background list sheet should move to, or `null` when it
/// should be left exactly where the user put it.
///
/// * [overlayOpen] — is the contact-profile sheet currently presented?
/// * [minExtent] — the list sheet's `minChildSize`.
/// * [currentExtent] — its current fractional extent.
///
/// Returns [minExtent] only when an overlay is open and the list sheet is
/// still taller than its minimum; otherwise `null` (no movement needed).
double? backgroundSheetTargetExtent({
  required bool overlayOpen,
  required double minExtent,
  required double currentExtent,
}) {
  if (!overlayOpen) return null;
  // Already at (or below) the collapsed handle — nothing to animate.
  if (currentExtent <= minExtent) return null;
  return minExtent;
}
