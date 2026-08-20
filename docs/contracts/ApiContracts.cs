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
/// <para>
/// Send them to <c>/auth/set-initial-password</c>, not <c>/auth/change-password</c>: they have
/// just proved they know the current password by signing in, so asking for it again is friction
/// with no security value.
/// </para>
/// </param>
/// <param name="CanOrderForGuests">
/// Whether this user may attach a guest's name to an order. Published so the client can show or
/// hide the guest field rather than letting the user fill one in and be rejected.
/// <para>
/// Authoritative only as of sign-in. The token lasts 30 days, and the server reads this privilege
/// from the token's claims — so a privilege granted or revoked today does not take effect for an
/// already-signed-in client until it gets a new token.
/// </para>
/// </param>
public sealed record LoginResponse(
    string Token,
    DateTime ExpiresUtc,
    string Username,
    string DisplayName,
    string Role,
    string Department,
    bool MustChangePassword,
    bool CanOrderForGuests);

public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);

/// <summary>
/// The first password a user chooses, replacing the seeded default.
/// <para>
/// Carries no current password on purpose: this endpoint is reachable only with a token whose
/// <c>must_change_password</c> claim is set, which is minted by signing in with the current
/// password moments earlier. Kept separate from <see cref="ChangePasswordRequest"/> rather than
/// making that type's current password optional, so a fault in the claim check cannot quietly
/// turn every password change into an unauthenticated one.
/// </para>
/// </summary>
public sealed record SetInitialPasswordRequest(string NewPassword);

/// <summary>An orderable item, with the caller's own balance of it when they have one.</summary>
/// <param name="HasOwnStock">
/// True when the caller owns some of this item. Says nothing about how much: it can be true with
/// <paramref name="OwnServingsLeft"/> at zero or below, because the ledger permits negative
/// balances by design. Group the item under "my materials" and warn — never disable it.
/// </param>
/// <param name="AllowedExtraItemIds">
/// Which extras this drink permits, or <b>null when it permits every extra</b> — the default for a
/// drink with no configured restriction. An empty list is different: it means no extras at all.
/// Never conflate the two.
/// <para>
/// Populated only on drinks; always null on sugars and extras, which have no extras of their own.
/// Filter the extras picker by this: an extra the drink does not permit is dropped server-side
/// while the order still succeeds, so a client that offers one produces a drink that arrives
/// wrong rather than an error the user can act on.
/// </para>
/// </param>
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
    IReadOnlyList<VariantDto> Variants,
    IReadOnlyList<int>? AllowedExtraItemIds);

/// <summary>
/// A way of preparing a drink. Empty for drinks made only one way, so the client can show the
/// selector only when there is a choice to make.
/// </summary>
/// <param name="IngredientItemIds">
/// Items this preparation already pours — the milk in a قهوة فرنساوي. Empty when the variant adds
/// nothing beyond the drink itself.
/// <para>
/// Published so the client can warn that choosing one of these as an <em>extra</em> means a second
/// portion and a second deduction. That doubling is correct — two pours, two deductions — but it is
/// the kind of correct that looks like a bug on the stock report if nobody said so first, which is
/// why the web order form marks it in two places.
/// </para>
/// <para>
/// <b>Annotate the extras picker with this; never filter it.</b> An ingredient is part of the
/// recipe and cannot be declined, which is exactly what separates it from
/// <see cref="CatalogueItemDto.AllowedExtraItemIds"/> — and a double portion is a legitimate thing
/// to order, so warn and let the user decide rather than disabling the choice.
/// </para>
/// <para>
/// Empty rather than null, unlike <see cref="CatalogueItemDto.AllowedExtraItemIds"/>: there is no
/// "unrestricted" case to distinguish here. A variant with no ingredients pours nothing extra,
/// which is what an empty list already says.
/// </para>
/// </param>
public sealed record VariantDto(
    int VariantId,
    string NameAr,
    string NameEn,
    bool IsDefault,
    IReadOnlyList<int> IngredientItemIds);

/// <summary>Everything the order screen needs, in one round trip.</summary>
/// <remarks>
/// Bundled deliberately: a phone on office wifi should not need four requests to draw one screen.
/// </remarks>
/// <param name="MaxLines">The most drinks one order may carry.</param>
/// <param name="MaxBuffetDrinks">
/// How many drinks on this order may come from the buffet's own stock; the rest must come from the
/// caller's own materials, or the order is rejected outright.
/// <para>
/// Published so the client can stop the user at the point of adding a drink rather than at the
/// point of submitting, and so the number lives in one place instead of being duplicated as a
/// magic constant. Counted on the source each line <b>resolves</b> to, not on the requested one:
/// asking for a jar the caller does not actually own falls back to buffet stock and counts here.
/// </para>
/// </param>
public sealed record CatalogueResponse(
    IReadOnlyList<CatalogueItemDto> Drinks,
    IReadOnlyList<CatalogueItemDto> Sugars,
    IReadOnlyList<CatalogueItemDto> Extras,
    IReadOnlyList<LocationDto> Locations,
    UsualOrderDto? Usual,
    int MaxLines,
    int MaxBuffetDrinks);

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
/// The item's picture as a root-relative path (<c>/uploads/items/12.png</c>), or null when the
/// admin never uploaded one — the normal case, which the client renders as a category glyph.
/// <para>
/// Relative on purpose, and so <b>unlike</b> <see cref="CatalogueItemDto.ImageUrl"/>, which is
/// absolute: the client resolves this against whichever API host it is pointed at, so a build
/// switched from staging to production does not have to strip a baked-in host out of the value.
/// A row can also outlive its file — the uploads folder is not covered by database backups — so a
/// 404 here is a fallback, not an error.
/// </para>
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

/// <summary>
/// A material the buffet does not carry at all, declared together with the private catalogue
/// entry it needs.
/// <para>
/// Kept separate from <see cref="DeclareMaterialRequest"/> rather than making that type's
/// <c>ItemId</c> nullable, for the same reason <see cref="SetInitialPasswordRequest"/> is
/// separate: one route that creates catalogue rows and one that only tops up existing ones
/// cannot be confused for each other, and a request that lost its id fails instead of quietly
/// creating a duplicate item.
/// </para>
/// </summary>
/// <param name="Category">
/// <c>"Drink"</c>, <c>"Sugar"</c> or <c>"Extra"</c> — by name, never the ordinal, as everywhere
/// else on this API.
/// </param>
/// <param name="Unit">
/// The base unit the other two amounts are counted in — جم, مل. Defaults to وحدة when omitted.
/// </param>
/// <param name="UnitsPerPackage">
/// How much one package holds, in <paramref name="Unit"/>. Must be positive: it is what
/// <paramref name="Quantity"/> is multiplied by.
/// </param>
/// <param name="UnitsPerServing">How much one cup uses. Must be positive; it sets the runway.</param>
/// <param name="Quantity">
/// How many <b>packages</b> were brought in — "I brought two 200g jars" is <c>2</c>. Fractions are
/// fine for a part-used packet.
/// <para>
/// Packages, unlike <see cref="DeclareMaterialRequest.Quantity"/>, which is in base units: the
/// caller has just said what one package holds, so asking again in grams only invites the two
/// numbers to disagree. This matches the web form, which has counted packages since its
/// base-unit field was removed for exactly that reason.
/// </para>
/// </param>
/// <remarks>
/// The item is created <b>unpublished</b> and stays invisible — including to its own owner's
/// order screen — until staff confirm the jar physically arrived. It will therefore <b>not</b>
/// appear in <c>/catalogue</c> after a successful call, and the client should say "awaiting
/// confirmation" rather than "added". No image on purpose: that needs multipart, and an item
/// without one falls back to the category glyph the client already draws.
/// </remarks>
public sealed record DeclareNewMaterialRequest(
    string NameAr,
    string Category,
    string? Unit,
    decimal UnitsPerPackage,
    decimal UnitsPerServing,
    decimal Quantity,
    string? Note);

/// <summary>Uniform error body, so the client has one shape to parse.</summary>
public sealed record ApiError(string Message);
