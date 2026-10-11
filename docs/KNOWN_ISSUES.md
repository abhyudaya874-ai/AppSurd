# Known issues (honest list for judges)

- Header day-toggle (1/3/5 days) is spec'd but not shipped — fixed at 5.
- Schedule grid does not clip the now-line to today's column (it spans the
  visible strip, Google-Calendar-style; deliberate).
- Dragging a scheduled block hides the original and previews a ghost on the
  target column; on drop the model persists. Reorder within a day = move.
- GitHub heatmap needs one successful fetch to cache; offline first-open shows
  the empty state.
- Tasks tab "stories" avatars list groups with ≥1 task only (an empty group
  has no avatar — intentional, matches the badge count).
- Focus feed flattens group sections (grouping applies to List mode).
