namespace BuffetApp.Web.Api;

// The staff half of the mobile client's wire format. Separate from the domain models for the same
// reason the employee contracts are: an entity reshaped for an internal reason must not silently
// change a contract a shipped app depends on.

/// <summary>A queue entry, seen from behind the counter.</summary>
/// <param name="RequesterDisplayName">Who ordered it — staff need the name, not just the username.</param>
/// <param name="WaitingSeconds">Seconds since the order was placed, for the ageing indicator.</param>
public sealed record StaffOrderDto(
    int OrderId,
    string Status,
    DateTime CreatedAtUtc,
    DateTime? ReadyAtUtc,
    string RequesterDisplayName,
    string Department,
    string LocationText,
    string? OnBehalfOfName,
    string Notes,
    int WaitingSeconds,
    IReadOnlyList<StaffOrderLineDto> Lines);

/// <summary>
/// One drink to make. Unlike the employee's <see cref="OrderLineDto"/>, sources are named rather
/// than flattened to "from own" booleans — those are computed relative to the caller, which is
/// meaningless to staff. The queue's whole job is saying which jar to reach for.
/// </summary>
/// <param name="DrinkSourceOwnerName">Empty string for company stock; otherwise the owner's display name.</param>
public sealed record StaffOrderLineDto(
    int DrinkItemId,
    string DrinkNameAr,
    string? VariantNameAr,
    int SugarSpoons,
    string? SugarNameAr,
    IReadOnlyList<string> ExtraNamesAr,
    string? LineNote,
    string DrinkSourceOwnerName,
    string SugarSourceOwnerName,
    IReadOnlyList<StaffExtraSourceDto> ExtraSources);

public sealed record StaffExtraSourceDto(int ItemId, string NameAr, string SourceOwnerName);

/// <summary>
/// The outcome of serving an order. Warnings ride in the body rather than an error status because
/// shortages never block: staff need to see them, and the drink was still made.
/// </summary>
public sealed record ServeResultDto(
    int OrderId,
    string Status,
    IReadOnlyList<StockWarningDto> Warnings);

/// <param name="Shortfall">How far below zero the balance went. Positive number.</param>
/// <param name="OwnerDisplayName">Empty string for company stock; otherwise whose jar ran short.</param>
public sealed record StockWarningDto(
    int ItemId, string NameAr, string OwnerDisplayName, decimal Shortfall, string Unit);

public sealed record DeclarationDto(
    int DeclarationId,
    string OwnerDisplayName,
    int ItemId,
    string NameAr,
    decimal Quantity,
    string Unit,
    string Note,
    DateTime CreatedAtUtc);

public sealed record CancelOrderRequest(string? Reason);

/// <param name="Quantity">
/// Omitted confirms the declared amount; supplied confirms a corrected one, for when the jar that
/// arrived is not the jar that was declared.
/// </param>
public sealed record ConfirmDeclarationRequest(decimal? Quantity);

public sealed record RejectDeclarationRequest(string? Reason);
