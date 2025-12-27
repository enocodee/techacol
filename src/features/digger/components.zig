const ecs_common = @import("ecs").common;

pub const DiggerBundle = struct {
    digger: Digger,
    /// TODO: this should be more variants
    shape: ecs_common.CircleBundle,
    in_grid: ecs_common.InGrid,
};

pub const Digger = struct {
    idx_in_grid: IndexInGrid,

    pub const IndexInGrid = struct {
        r: i32,
        c: i32,
    };
};
