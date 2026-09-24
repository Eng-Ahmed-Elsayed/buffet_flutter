/// Fixtures for the design-review screenshot run.
///
/// Deliberately *worst-case-but-real* data rather than tidy placeholders: long
/// Arabic names, a guest order, a note, a negative material balance, a
/// shortage. A designer reviewing tidy data approves a layout that breaks on
/// the first real order.
library;

import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';

CatalogueItemDto drink(
  int id,
  String ar,
  String en, {
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
  bool inStock = true,
  List<VariantDto> variants = const [],
  String category = 'Drink',
}) => CatalogueItemDto(
  itemId: id,
  nameAr: ar,
  nameEn: en,
  category: category,
  unit: 'جرام',
  imageUrl: null,
  inStock: inStock,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: variants,
  allowedExtraItemIds: null,
);

/// A catalogue with the shapes that matter: a drink with preparations, one
/// drawn from the user's own jar, one out of stock, sugars and extras.
final catalogue = CatalogueResponse(
  drinks: [
    drink(
      1,
      'قهوة تركي سادة',
      'Turkish coffee',
      variants: const [
        VariantDto(
          variantId: 11,
          nameAr: 'غامق',
          nameEn: 'Dark',
          isDefault: true,
        ),
        VariantDto(
          variantId: 12,
          nameAr: 'وسط',
          nameEn: 'Medium',
          isDefault: false,
        ),
      ],
    ),
    drink(2, 'شاي بالنعناع', 'Mint tea', hasOwnStock: true, ownServingsLeft: 4),
    drink(3, 'نسكافيه بالحليب', 'Nescafe with milk'),
    drink(4, 'كابتشينو', 'Cappuccino', inStock: false),
  ],
  sugars: [
    drink(
      20,
      'سكر أبيض',
      'White sugar',
      category: 'Sugar',
      hasOwnStock: true,
      ownServingsLeft: 12,
    ),
  ],
  extras: [
    drink(30, 'حليب', 'Milk', category: 'Extra'),
    drink(31, 'قرفة', 'Cinnamon', category: 'Extra'),
  ],
  locations: const [
    LocationDto(locationId: 40, nameAr: 'الدور الثالث', kind: 'Floor'),
    LocationDto(locationId: 41, nameAr: 'قاعة الاجتماعات', kind: 'Room'),
  ],
  maxLines: 5,
  maxBuffetDrinks: 2,
);

/// An empty catalogue — the state an admin's unfinished import leaves behind.
const emptyCatalogue = CatalogueResponse(
  drinks: [],
  sugars: [],
  extras: [],
  locations: [],
  maxLines: 5,
  maxBuffetDrinks: 2,
);

OrderSummaryDto order(
  int id,
  String status, {
  String? onBehalfOfName,
  String notes = '',
  String locationText = 'الدور الثالث، مكتب ٣١٢',
  DateTime? readyAtUtc,
}) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 9, 19, 7),
  readyAtUtc: readyAtUtc,
  handledAtUtc: null,
  locationText: locationText,
  onBehalfOfName: onBehalfOfName,
  notes: notes,
  lines: const [
    OrderLineDto(
      drinkItemId: 1,
      drinkNameAr: 'قهوة تركي سادة',
      sugarSpoons: 2,
      variantId: 11,
      sugarItemId: null,
      extraItemIds: [30],
      lineNote: null,
      drinkFromOwn: true,
      sugarFromOwn: false,
      ownExtraItemIds: [],
    ),
  ],
);

final orders = [
  order(
    142,
    'Ready',
    onBehalfOfName: 'وفد وزارة الاتصالات',
    notes: 'بدون لبن من فضلك',
    readyAtUtc: DateTime.utc(2026, 9, 19, 7, 6),
  ),
  order(141, 'InProgress'),
  order(138, 'Completed', locationText: ''),
  order(137, 'Cancelled', locationText: ''),
];

FavouriteDto favourite(int id, String name, {DateTime? lastUsedAtUtc}) =>
    FavouriteDto(
      favouriteId: id,
      name: name,
      createdAtUtc: DateTime.utc(2026, 9, 1),
      lastUsedAtUtc: lastUsedAtUtc,
      lines: const [],
    );

final favourites = [
  favourite(1, 'قهوتي الصباحية', lastUsedAtUtc: DateTime.utc(2026, 9, 19, 6)),
  favourite(
    2,
    'قهوة تركي سادة (بدون سكر) + حليب، شاي بالنعناع (١ سكر)',
    lastUsedAtUtc: DateTime.utc(2026, 9, 18, 6),
  ),
  favourite(3, 'شاي خفيف', lastUsedAtUtc: DateTime.utc(2026, 9, 17, 6)),
  favourite(4, 'نسكافيه مزدوج', lastUsedAtUtc: DateTime.utc(2026, 9, 16, 6)),
  favourite(5, 'كابتشينو للزائر', lastUsedAtUtc: DateTime.utc(2026, 9, 15, 6)),
];

final materials = [
  const MyMaterialDto(
    itemId: 1,
    nameAr: 'قهوة تركي محوجة درجة أولى',
    unit: 'جرام',
    quantity: 320,
    servingsLeft: 26,
    level: 'Ok',
    imageUrl: null,
  ),
  const MyMaterialDto(
    itemId: 2,
    nameAr: 'شاي بالنعناع',
    unit: 'جرام',
    quantity: 40.5,
    servingsLeft: 3,
    level: 'Low',
    imageUrl: null,
  ),
  const MyMaterialDto(
    itemId: 3,
    nameAr: 'سكر أبيض',
    unit: 'جرام',
    quantity: -250.5,
    servingsLeft: 0,
    level: 'Out',
    imageUrl: null,
  ),
];

final notifications = [
  NotificationDto(
    notificationId: 1,
    kind: 'OrderReady',
    message: 'مشروبك رقم ١٤٢ جاهز للاستلام من البوفيه في الدور الثالث',
    orderId: 142,
    createdAtUtc: DateTime.utc(2026, 9, 19, 7, 6),
    isRead: false,
  ),
  NotificationDto(
    notificationId: 2,
    kind: 'LowStock',
    message: 'مخزونك من الشاي بالنعناع يكفي ٣ أكواب فقط',
    orderId: null,
    createdAtUtc: DateTime.utc(2026, 9, 19, 6, 30),
    isRead: false,
  ),
  NotificationDto(
    notificationId: 3,
    kind: 'DeclarationConfirmed',
    message: 'تم تأكيد استلام ٥٠٠ جرام قهوة تركي محوجة درجة أولى',
    orderId: null,
    createdAtUtc: DateTime.utc(2026, 9, 18, 9),
    isRead: true,
  ),
  NotificationDto(
    notificationId: 4,
    kind: 'DeclarationRejected',
    message: 'لم يتم تأكيد إضافة السكر، يرجى مراجعة البوفيه',
    orderId: null,
    createdAtUtc: DateTime.utc(2026, 9, 17, 11),
    isRead: true,
  ),
  NotificationDto(
    notificationId: 5,
    kind: 'OrderCancelled',
    message: 'تم إلغاء طلبك رقم ١٣٧ بسبب نفاد الكابتشينو',
    orderId: 137,
    createdAtUtc: DateTime.utc(2026, 9, 17, 8),
    isRead: true,
  ),
];

StaffOrderDto staffOrder(
  int id, {
  String status = 'Pending',
  String requester = 'سارة عبد الرحمن',
  String department = 'الشؤون المالية والإدارية',
  String? onBehalfOfName,
  String notes = '',
  int waitingSeconds = 120,
  List<StaffOrderLineDto>? lines,
  DateTime? readyAtUtc,
}) => StaffOrderDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 9, 19, 7),
  readyAtUtc: readyAtUtc,
  requesterDisplayName: requester,
  department: department,
  locationText: 'الدور الثالث، مكتب ٣١٢',
  onBehalfOfName: onBehalfOfName,
  notes: notes,
  waitingSeconds: waitingSeconds,
  lines:
      lines ??
      const [
        StaffOrderLineDto(
          drinkItemId: 1,
          drinkNameAr: 'قهوة تركي سادة',
          variantNameAr: 'غامق',
          sugarSpoons: 2,
          sugarNameAr: null,
          extraNamesAr: ['حليب'],
          lineNote: null,
          drinkSourceOwnerName: '',
          sugarSourceOwnerName: '',
          extraSources: [],
        ),
      ],
);

/// The queue as it looks under a rush: a worst-case card carrying a guest, a
/// note, a preparation and an own-jar line, plus two ordinary ones.
final staffQueue = [
  staffOrder(
    41,
    onBehalfOfName: 'وفد وزارة الاتصالات',
    notes: 'بدون لبن من فضلك، والكوب كبير',
    waitingSeconds: 640,
    lines: const [
      StaffOrderLineDto(
        drinkItemId: 1,
        drinkNameAr: 'قهوة تركي سادة',
        variantNameAr: 'غامق',
        sugarSpoons: 2,
        sugarNameAr: null,
        extraNamesAr: ['حليب', 'قرفة'],
        lineNote: 'كوب كبير',
        drinkSourceOwnerName: 'سارة عبد الرحمن',
        sugarSourceOwnerName: '',
        extraSources: [],
      ),
      StaffOrderLineDto(
        drinkItemId: 2,
        drinkNameAr: 'شاي بالنعناع',
        variantNameAr: null,
        sugarSpoons: 0,
        sugarNameAr: null,
        extraNamesAr: [],
        lineNote: null,
        drinkSourceOwnerName: '',
        sugarSourceOwnerName: '',
        extraSources: [],
      ),
    ],
  ),
  staffOrder(
    42,
    status: 'InProgress',
    requester: 'محمد الشريف',
    department: 'تقنية المعلومات',
    waitingSeconds: 95,
  ),
  staffOrder(
    43,
    requester: 'نورة القحطاني',
    department: 'الموارد البشرية',
    waitingSeconds: 20,
  ),
];

final staffHandovers = [
  staffOrder(
    39,
    status: 'Ready',
    requester: 'خالد المطيري',
    department: 'الشؤون القانونية',
    readyAtUtc: DateTime.utc(2026, 9, 19, 7, 4),
  ),
  staffOrder(
    40,
    status: 'Ready',
    requester: 'سارة عبد الرحمن',
    department: 'الشؤون المالية والإدارية',
    onBehalfOfName: 'وفد وزارة الاتصالات',
    readyAtUtc: DateTime.utc(2026, 9, 19, 7, 5),
  ),
];

/// Shortages are `200`-with-warnings, never a failure: the drink was made.
final shortageWarnings = [
  const StockWarningDto(
    itemId: 20,
    nameAr: 'سكر أبيض',
    ownerDisplayName: '',
    shortfall: 12.5,
    unit: 'جرام',
  ),
  const StockWarningDto(
    itemId: 2,
    nameAr: 'شاي بالنعناع',
    ownerDisplayName: 'سارة عبد الرحمن',
    shortfall: 3,
    unit: 'جرام',
  ),
];
