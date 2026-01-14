const std = @import("std");
const query_filter = @import("query/filter.zig");
const query_util = @import("query/utils.zig");
const ecs_util = @import("util.zig");

const ErasedComponentStorage = @import("component.zig").ErasedStorage;
const World = @import("World.zig");
const EntityID = @import("Entity.zig").ID;

pub const QueryError = error{OutOfMemory} || World.GetComponentError;

pub const filter = struct {
    pub const With = query_filter.With;
    pub const Without = query_filter.Without;
};

/// A wrapper for automatically querying a specified entity
/// components that should be called in `system.toHandler`.
pub fn Query(comptime types: []const type) type {
    comptime if (types.len <= 0)
        @compileError("Cannot use `Query` with empty arguments");

    const queried_type = comptime get_queried: {
        var count_valid = 0;
        for (types) |T| {
            if (!query_filter.isFilter(T)) {
                count_valid += 1;
            }
        }
        if (count_valid == 0)
            @compileError("There aren't any valid component to query.");

        var final_types: [count_valid]type = undefined;
        var curr_i = 0;
        for (types) |T| {
            if (!query_filter.isFilter(T)) {
                final_types[curr_i] = T;
                curr_i += 1;
            }
        }
        break :get_queried final_types;
    };

    comptime var exclude_types: []const type = &[_]type{};

    // NOTE: flatten all types in the query filter to use in order to
    //       retrieve all entities IDs
    const flatten_type = comptime get_flatten: {
        var count_valid = 0;
        for (types) |T| {
            if (query_filter.isFilter(T)) {
                if (T.getKind() == .without) continue;
                count_valid += T._types.len;
            } else {
                count_valid += 1;
            }
        }

        var final_types: [count_valid]type = undefined;
        var curr_i = 0;
        blk: for (types) |T| {
            if (query_filter.isFilter(T)) {
                switch (T.getKind()) {
                    .with => for (T._types) |FilterType| {
                        final_types[curr_i] = FilterType;
                        curr_i += 1;
                    },
                    .without => {
                        exclude_types = exclude_types ++ T._types;
                        break :blk;
                    },
                }
            } else {
                final_types[curr_i] = T;
                curr_i += 1;
            }
        }
        break :get_flatten final_types;
    };

    return struct {
        result: Result = .{},

        pub const Result = struct {
            /// Contains all types ordered by `types` but
            /// exclude all types inside `QueryFilter`.
            tuples: []Tuple = &.{},

            /// return the first result element
            pub fn single(self: Result) Tuple {
                return self.tuples[0];
            }

            // return all result elements
            pub fn many(self: Result) []Tuple {
                return self.tuples;
            }

            /// return the first result element
            pub fn singleOrNull(self: Result) ?Tuple {
                return if (self.tuples.len <= 0) null else self.tuples[0];
            }
        };

        pub const Tuple = std.meta.Tuple(&queried_type);

        const Self = @This();

        /// Fetch all entities that have **all** of the speicifed component types.
        /// Return a slice of tuples, each tuple being a group of values of an entity.
        ///
        /// # Examples:
        /// Query directly:
        /// ---
        /// ```zig
        /// const query = try Query(&.{Position, Velocity}).query();
        /// const result = query.result; // get the result
        /// for (result) |entity| {
        ///     const pos: Position, const vec: Velocity = entity;
        ///     ...
        /// }
        /// ```
        /// ---
        /// or you can define the type in systems as arguments:
        /// ---
        /// ```zig
        /// fn yourSystem(queries: Query(&.{Position, Velocity})) !void {
        ///     const result = queries.result;
        ///     // do something
        /// }
        /// ```
        /// ---
        ///
        /// This function should be used in `systems` (called in every frame),
        /// so we can ensure that all allocated things will be freed at the
        /// end of the frame.
        ///
        /// See `query.QueryFilter` for more details about the filters.
        pub fn query(self: *Self, w: World) QueryError!void {
            const alloc = w.arena.allocator();
            // Temporary list containing entity ids for each component storage
            var temp_list: std.ArrayList(EntityID) = .empty;
            const min_storage = try query_util.getKeysOfMinStorage(w, &flatten_type);
            // init the query list with the storage containing the fewest elements
            var query_list: std.ArrayList(EntityID) = .fromOwnedSlice(min_storage.items);
            // list containing all types whose all keys should not be queried
            var exclude_list: std.AutoHashMap(EntityID, EntityID) = .init(w.arena.allocator());
            var final_list: std.ArrayList(EntityID) = .empty;

            inline for (exclude_types) |T| {
                // use label to control flow in comptime
                const Type = ecs_util.Deref(T);
                const s = try ErasedComponentStorage.cast(w, Type);

                var data_iter = s.data.keyIterator();
                while (data_iter.next()) |it| {
                    try exclude_list.put(it.*, it.*);
                }
            }

            inline for (flatten_type, 0..) |T, i| {
                // use label to control flow in comptime
                skip_min: {
                    // skip the min_storage because its available
                    // in the result list
                    if (i == min_storage.idx) break :skip_min;

                    const Type = ecs_util.Deref(T);
                    const s = try ErasedComponentStorage.cast(w, Type);

                    var data_iter = s.data.keyIterator();
                    while (data_iter.next()) |it| {
                        try temp_list.append(alloc, it.*);
                    }
                    try query_util.findIdentical(alloc, &query_list, temp_list);

                    // reset l1
                    temp_list.clearAndFree(alloc);
                }
            }

            for (query_list.items) |it| {
                if (!exclude_list.contains(it)) {
                    try final_list.append(alloc, it);
                }
            }

            self.result.tuples = try query_util.tuplesFromTypes(w, final_list.items, &queried_type);
        }

        /// return the first result element
        pub fn single(self: Self) Tuple {
            return self.result.single();
        }

        // return all result elements
        pub fn many(self: Self) []Tuple {
            return self.result.many();
        }
    };
}
