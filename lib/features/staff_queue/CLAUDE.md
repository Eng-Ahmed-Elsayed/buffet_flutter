# Staff queue

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
rules a future edit must not undo. The root file's Standing rules and Domain rules still apply here.

Rules a future edit must not undo:

- **The staff undo affordance lives on the card, not in a SnackBar.** `ScaffoldMessenger` *queues*
  snackbars and their duration counts from display, not creation, so a rush showed undo buttons for
  orders that had already been served. Do not "simplify" it back.
- **A committed serve's card goes at once and stays gone until its answer lands.** It is removed
  as the undo window commits (as a handover's is) and filtered out of every refresh while its
  `/ready` is in flight (`_serving`): a poll answered first still lists it Pending, and live Ready
  buttons coming back read as "undone" and got the drink made twice. Put back only if the serve fails.
  **A shortage from "ready and handed over" is shown above the tabs**, named, until dismissed,
  since that order leaves both lists and its card with it. `queue_serve_test.dart`.
- **A refresh older than this device's last change is dropped** (`_mutationEpoch`, bumped when a
  card is taken off and when a serve, handover, start or cancel answers). Clearing `_serving`
  alone was not enough: a poll sent before `/ready` answered, landing after it, still listed the
  order Pending and brought its Ready buttons back. The refresh that follows every change brings
  the truth. `queue_stale_poll_test.dart`.
- **New orders sound and vibrate, once per refresh** (`NewOrderDetector`, `_alertForNew`;
  approved 2026-11-20). Staff get no push, so this is how a new order is heard at the counter
  while the app is open. One local notification on the `new_order` channel (a fixed id, so a
  second batch replaces the first, and no payload) plus `HapticFeedback.vibrate`, however many
  orders arrived. **Never** on the first load (the queue as it was), **never** on the refresh
  that catches up after a resume (the person has just opened the screen showing them; those ids
  are marked seen, not announced later), **never** for an order this device placed
  (`selfPlacedOrdersProvider`, written by the composer), and not at all when switched off in
  staff settings (`pref_queue_alerts`, on by default, a device setting that survives sign-out).
  Every id ever shown is remembered, so a stale poll dropped by `_mutationEpoch`, or an order
  put back after a failed serve, never alerts twice. No wakelock: the screen may sleep.
  `queue_new_order_alert_test.dart`.
- **The pending bar is announced once, with the seconds left when it appeared.** Its live region
  used to carry the ticking count and was re-read every second. There is no press-to-pause: it
  stopped the bar but not the commit, so the bar lied. **A handover card can be cancelled**: the
  server re-books a Ready order's consumption as waste, and the dialog says so. The dialog's buttons
  are "Keep order" and "Cancel order", never "Cancel"/"Confirm". Identical cups show once with ×N,
  where identical means every field the maker acts on. The two tabs carry their counts, scroll
  and grow in height rather than fade a label (`measureTabLabels`). **"Start making" (`/start`)
  is optional, never a gate**: a Pending card offers it above the ready pair, which still serve a
  Pending order directly, and an InProgress card says "being made" in its place. **The card says
  how the drink leaves the counter** (§8.1): "Deliver to {location}", or "Collecting from the
  kitchen" with the location kept as where the person sits; an order with no mode shows the
  location alone. It is a text
  button, so Ready stays the largest target. It is immediate, with no undo, since it writes no
  ledger rows, and it is announced. `queue_staff_view_test.dart`.
