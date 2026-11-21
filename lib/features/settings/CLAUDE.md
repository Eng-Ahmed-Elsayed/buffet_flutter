# Account tab

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
 The root file's Standing rules and Domain rules still apply here.

**The Account tab is the design's Settings frame**: the name and department, then stacked card
rows. The rows are My materials (employees only), Change password, the biometric switch (its own
card, drawn only on a device that can use it), Language, and Sign out in `danger`. **Change password
is `/password`, a separate route from the forced `/change-password`**, and the same screen serves
both by reading the auth stage. Signed in, it asks for the current password and pops with a
confirmation. Forced, it never asks for the current password and never lets the user back. The
forced stage bounces every route, `/password` included, so rule 10 holds without a special case.
Staff (the same screen pushed from the queue) also get **"Alert me to new orders"**, a switch
card after the biometric one, on by default (see `staff_queue/CLAUDE.md`); employees never see it.
The design's Version line is at the foot, from `package_info_plus` (`appVersionProvider`),
with the build number after it.
