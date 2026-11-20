# Home

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
the shell's back and push rules stay in the root file. The root file's Standing rules and Domain rules still apply here.

**Employees land in a bottom-nav shell** (`lib/app/employee_shell.dart`, a
`StatefulShellRoute`): **Home · Favourites · Orders · Account** at `/home`, `/favourites`,
`/orders`, `/account`. Home is the design's Home: greeting, drink search (`foldForSearch`, which
treats «قهوه» and «قهوة» as the same), the outstanding-order card, the favourites strip and the menu
of every drink grouped «من موادي» then «من البوفيه». **Menu groups filter both sections** (All, each
group, and «أخرى» for a drink with none or a retired one); with no groups the chips jump to the two
jars instead. A row shows two lines of description, Drink Details the whole
(`menu_groups_test.dart`). **There is no "New order" button; a menu row
is the way in.** It opens the composer seeded with `ComposerSeed.drinkItemId` and `drinkFromOwn`,
the row's jar. Home builds its whole menu (a `Column`, not a lazy `ListView`), because the jump
chips scroll to a section heading and a lazy list never builds an off-screen one. My materials is a
row on Account. Staff still land on `/queue`, with no bar, and
push what they need from there. Each role has exactly one landing, and `signedInRedirect` (in
`router.dart`, tested directly by `landing_route_test.dart`) bounces staff off every tab and
employees off the queue. The shell's three navigation rules are in the root CLAUDE.md.

**One destination, one control per screen.** The bell lives in Home's top bar **only**; settings
is the Account tab, and My orders is the Orders tab. None of them has a tile or an icon on Home as
well, because the same destination twice on one screen (once in the chrome, once in the body) is
noise. The unread badge lives on the bell alone for the same reason. Pinned by
`test/features/home_screen_test.dart`.
