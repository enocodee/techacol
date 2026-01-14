pub fn With(comptime types: []const type) type {
    return QueryFilter(.with, types);
}

pub fn Without(comptime types: []const type) type {
    return QueryFilter(.without, types);
}

const QueryFilterKind = enum {
    with,
    without,
};

pub fn QueryFilter(comptime kind: QueryFilterKind, comptime types: []const type) type {
    return struct {
        // NOTE: define a field to determine which the filter is used.
        _kind: QueryFilterKind = kind,

        // NOTE: avoid to use field `[]const type` that forces entire
        //       the caller known at comptime.
        pub const _types: []const type = types;

        pub fn getKind() QueryFilterKind {
            return kind;
        }
    };
}

pub fn isFilter(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasField(T, "_kind") and @FieldType(T, "_kind") == QueryFilterKind;
}
