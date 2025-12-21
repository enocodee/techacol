const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const World = @import("World.zig");

pub const Handler = *const fn (*World) anyerror!void;

pub const System = struct {
    handler: Handler,
    order: ExecOrder,

    pub const ExecOrder = enum {
        startup,
        update,
    };
};

/// Convert `system` to `handler` with wired params.
pub fn systemHandler(comptime system: anytype) Handler {
    const H = struct {
        pub fn handle(w: *World) !void {
            const SystemType = @TypeOf(system);
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
