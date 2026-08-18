using BuffetApp.Core.Enums;

namespace BuffetApp.Web.Api;

// The mobile client's wire format. Deliberately separate from the domain models: an entity
// reshaped for an internal reason must not silently change the contract a shipped app depends
// on, and these must never carry a password hash.

/// <param name="Username">Email address.</param>
public sealed record LoginRequest(string Username, string Password);

/// <param name="MustChangePassword">
/// When true the client must send the user to a change-password screen before ordering; the
/// token works, but the account is still on its seeded password.
/// </param>
public sealed record LoginResponse(
    string Token,
    DateTime ExpiresUtc,
    string Username,
    string DisplayName,
    string Role,
    string Department,
    bool MustChangePassword);

public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);

/// <summary>An orderable item, with the caller's own balance of it when they have one.</summary>
public sealed record CatalogueItemDto(
    int ItemId,
    string NameAr,
    string NameEn,
    string Category,
    string Unit,
    string? ImageUrl,
    bool InStock,
    bool HasOwnStock,
    int OwnServingsLeft,
    IReadOnlyList<VariantDto> Variants);

/// <summary>
/// A way of preparing a drink. Empty for drinks made only one way, so the client can show the
/// selector only when there is a choice to make.
/// </summary>
public sealed record VariantDto(int VariantId, string NameAr, string NameEn, bool IsDefault);

/// <summary>Everything the order screen needs, in one round trip.</summary>
/// <remarks>
/// Bundled deliberately: a phone on office wifi should not need four requests to draw one screen.
/// </remarks>
public sealed record CatalogueResponse(
    IReadOnlyList<CatalogueItemDto> Drinks,
    IReadOnlyList<CatalogueItemDto> Sugars,
    IReadOnlyList<CatalogueItemDto> Extras,
    IReadOnlyList<LocationDto> Locations,
    UsualOrderDto? Usual);

public sealed record LocationDto(int LocationId, string NameAr, string Kind);

/// <summary>The caller's last order, for a one-tap repeat.</summary>
public sealed record UsualOrderDto(string Summary, IReadOnlyList<OrderLineDto> Lines);

public sealed record OrderLineDto(
    int DrinkItemId,
    string DrinkNameAr,
    int SugarSpoons,
    int? VariantId,
    int? SugarItemId,
    IReadOnlyList<int> ExtraItemIds,
    string? LineNote,
    bool DrinkFromOwn,
    bool SugarFromOwn,
    IReadOnlyList<int> OwnExtraItemIds);

public sealed record PlaceOrderApiRequest(
    IReadOnlyList<OrderLineDto> Lines,
    string? Notes,
    int? LocationId,
    string? LocationText,
    string? OnBehalfOfName,
    /// <summary>
    /// Client-generated key. Send the same value when retrying so a dropped response cannot
    /// become a second drink.
    /// </summary>
    string? IdempotencyKey);

/// <param name="Duplicate">True when an existing order matched the idempotency key.</param>
public sealed record PlaceOrderResponse(int OrderId, bool Duplicate);

public sealed record OrderSummaryDto(
    int OrderId,
    string Status,
    DateTime CreatedAtUtc,
    DateTime? ReadyAtUtc,
    DateTime? HandledAtUtc,
    string LocationText,
    string? OnBehalfOfName,
    string Notes,
    IReadOnlyList<OrderLineDto> Lines)
{
    /// <summary>True once the drink has been made, so the client can show a "collect it" prompt.</summary>
    public bool IsReady => Status == nameof(OrderStatus.Ready);
}

public sealed record NotificationDto(
    int NotificationId,
    string Kind,
    string Message,
    int? OrderId,
    DateTime CreatedAtUtc,
    bool IsRead);

/// <summary>One of the caller's own materials.</summary>
/// <param name="ImageUrl">
/// Relative path (resolved against the API host), as on <see cref="CatalogueItemDto"/>. Null when
/// the item has no uploaded image — the client falls back to a category glyph. A 404 on the file
/// is "use the fallback", not an error.
/// PENDING: not yet returned by the API. See docs/backend-request-material-image.md.
/// </param>
public sealed record MyMaterialDto(
    int ItemId,
    string NameAr,
    string Unit,
    decimal Quantity,
    int ServingsLeft,
    string Level,
    string? ImageUrl);

public sealed record DeclareMaterialRequest(int ItemId, decimal Quantity, string? Note);

/// <summary>Uniform error body, so the client has one shape to parse.</summary>
public sealed record ApiError(string Message);
