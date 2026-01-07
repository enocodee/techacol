//! A namepsace that contains all thing related to `system`.
//!
//! Systems define how controlling elements (entity, component,
//! resource, ...) in application.
const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const World = @import("World.zig");

pub const Handler = *const fn (*World) anyerror!void;

/// A component represent for `systems`
pub const System = struct {
    handler: Handler,

    pub const Config = struct {
        in_sets: []const Set = &.{},
    };

    pub fn fromFn(comptime system: anytype) System {
        const Fn = @TypeOf(system);
        const fn_info = @typeInfo(Fn);
        if (fn_info != .@"fn")
            @compileError("expected a function, found " ++ @typeName(Fn));

        const ret_info = @typeInfo(fn_info.@"fn".return_type.?);
        if (ret_info == .error_union) {
            const error_union = ret_info.error_union;
            if (error_union.payload != void)
                @compileError("the system return type must be `anyerror!void`, found `anyerror!" ++ @typeName(error_union.payload) ++ "`");
        } else {
            @compileError("the system return type must be `anyerror!void`, found " ++ @typeName(fn_info.@"fn".return_type.?));
        }

        return .{
            .handler = toHandler(system),
        };
    }
};

// A group of systems
pub const Set = struct {
    name: []const u8,

    pub const Config = struct {
        after: []const Set = &.{},
        before: []const Set = &.{},
    };

    pub inline fn eql(self: Set, another: Set) bool {
        return std.mem.eql(u8, self.name, another.name);
    }
};

/// Convert `system` to `handler` with wired params.
pub fn toHandler(comptime system: anytype) Handler {
    const H = struct {
        pub fn handle(w: *World) !void {
            const SystemType = @TypeOf(system);
            // SAFETY: assign after parsing
            var args: std.meta.ArgsTuple(SystemType) = undefined;
            const system_info = @typeInfo(SystemType).@"fn";

            inline for (system_info.params, 0..) |param, i| {
                switch (param.type.?) {
                    *World => args[i] = w,
                    *Arena => args[i] = w.arena,
                    Allocator => args[i] = w.alloc,
                    else => {
                        const T = param.type.?;
                        if (T == World) continue;

                        // Query(...)
                        // NOTE: This allow custom query functions
                        if (@hasDecl(T, "query")) {
                            var obj: T = .{};
                            try obj.query(w.*);
                            args[i] = obj;
                        }
                    },
                }
            }

            try @call(.auto, system, args);
        }
    };

    return &H.handle;
}
