// TODO:
// - Finish writing tests
// - Change leaf to have slices and finalize API
// - Add next field in leaf struct to support iteration
// - Embed in larger buffer struct and remove alloc field
// - Benchmark?

const std = @import("std");
const Allocator = std.mem.Allocator;

root: NodeID,
branches: std.MultiArrayList(Branch) = .empty,
leaves: std.MultiArrayList(Leaf) = .empty,
alloc: Allocator,

const Self = @This();

const NodeID = union(enum) {
    leaf: u32,
    branch: u32,

    pub fn getBranch(self: NodeID) ?u32 {
        return switch (self) {
            .leaf => null,
            .branch => |branch_i| branch_i,
        };
    }
};

const Branch = struct {
    children: [2]NodeID = undefined, // left, right
    parent: ?u32 = null,
    offset: u32,
    color: enum { black, red } = .black,
};

const Leaf = struct {
    offset: u32,
    value: u32, // Placeholder
};

pub fn deinit(self: *Self) void {
    self.branches.deinit(self.alloc);
    self.leaves.deinit(self.alloc);
}

pub fn insert(self: *Self, offset: u32, value: u32) !void {
    try self.leaves.append(self.alloc, .{ .offset = offset, .value = value });
    const i: u32 = @intCast(self.leaves.len - 1);

    var node_i = self.root;
    const offsets = self.leaves.items(.offset);
    var parent: ?u32 = null;
    var right: bool = undefined;
    while (true) {
        switch (node_i) {
            .branch => |branch_i| {
                const branch = self.branches.get(branch_i);
                parent = branch_i;
                right = offset >= branch.offset;
                node_i = branch.children[@intFromBool(right)];
            },
            .leaf => |leaf_i| {
                const leaf_offset = offsets[leaf_i];
                right = offset >= leaf_offset;
                var branch: Branch = .{
                    .color = .red,
                    .offset = if (right) leaf_offset else offset,
                    .parent = parent,
                };
                branch.children[@intFromBool(right)] = .{ .leaf = i };
                branch.children[@intFromBool(!right)] = .{ .leaf = leaf_i };

                const branch_i: NodeID = .{ .branch = @intCast(self.branches.len) };

                if (std.meta.eql(node_i, self.root)) {
                    self.root = branch_i;
                    branch.color = .black;
                }

                try self.branches.append(self.alloc, branch);

                if (parent) |parent_i| {
                    var parent_node = self.branches.get(parent_i);
                    parent_node.children[@intFromBool(right)] = branch_i;
                    self.branches.set(parent_i, parent_node);
                }

                self.rebalance(branch_i.branch);
                break;
            },
        }
    }
}

// Traverse up the tree and check colors/rebalance
fn rebalance(self: *Self, branch_i: u32) void {
    var branches = self.branches.slice();
    var colors = branches.items(.color);
    var color = colors[branch_i];
    var parents = branches.items(.parent);
    var childrens = branches.items(.children);
    var node_i = branch_i;

    while (parents[node_i]) |parent_i| : ({
        node_i = parent_i;
        color = colors[parent_i];
    }) {
        if (color == .red and colors[parent_i] == .red) {
            // Check uncle and switch colors, rebalance as necessary
            const grandparent_i = parents[parent_i] orelse continue;
            const children = childrens[grandparent_i];
            // Have to use eql here because the child could be a leaf
            const right = std.meta.eql(children[1], .{ .branch = parent_i });
            const right_i = @intFromBool(right);
            const left_i = 1 - right_i;
            const uncle_i = children[left_i];

            switch (uncle_i) {
                .branch => |uncle_branch_i| { // Recolor
                    colors[parent_i] = .black;
                    colors[uncle_branch_i] = .black;
                },
                .leaf => { // Rotate
                    childrens[grandparent_i][right_i] = childrens[parent_i][left_i];
                    childrens[parent_i][left_i] = .{ .branch = grandparent_i };
                    parents[parent_i] = parents[grandparent_i];
                    parents[grandparent_i] = parent_i;

                    colors[parent_i] = .black;
                    colors[grandparent_i] = .red;

                    if (self.root.branch == grandparent_i) self.root.branch = parent_i;
                    if (parents[parent_i]) |greatgrandparent_i| {
                        childrens[greatgrandparent_i][right_i] = .{ .branch = parent_i };
                    }
                },
            }
        }
    }
}

pub const ValidationError = error {
    RootIsRed,
    AdjacentReds,
    UnevenBlacks,
};

pub fn validate(self: *const Self) ValidationError!void {
    if (self.root.getBranch()) |branch_i| {
        const colors = self.branches.items(.color);
        if (colors[branch_i] == .red) return error.RootIsRed;
    } else return;

    _ = try self.validate_node(self.root, false);
}

fn validate_node(self: *const Self, node_i: NodeID, red: bool) ValidationError!u32 {
    switch (node_i) {
        .leaf => return 0,
        .branch => |branch_i| {
            const branch = self.branches.get(branch_i);
            const new_red = branch.color == .red;
            if (red and new_red) return error.AdjacentReds;

            const left_blacks = try self.validate_node(branch.children[0], new_red);
            const right_blacks = try self.validate_node(branch.children[1], new_red);
            if (left_blacks != right_blacks) return error.UnevenBlacks;

            return left_blacks + @intFromBool(!new_red);
        },
    }
}

// Even after I implement next indices on the leaves,
// this function will be necessary for testing because
// relying on my implementation would make the test
// cases unreliable.
//
// Caller owns returned slice.
pub fn inorder(self: *const Self, alloc: Allocator) ![]u32 {
    var values: std.ArrayList(u32) = .init(alloc);

    try self.inorderNode(self.root, &values);

    return try values.toOwnedSlice();
}

fn inorderNode(self: *const Self, node_i: NodeID, values: *std.ArrayList(u32)) !void {
    switch (node_i) {
        .leaf => |leaf_i| {
            const leaf_values = self.leaves.items(.value);
            try values.append(leaf_values[leaf_i]);
        },
        .branch => |branch_i| {
            const children = self.branches.items(.children)[branch_i];
            try self.inorderNode(children[0], values);
            try self.inorderNode(children[1], values);
        },
    }
}

pub fn print(self: *const Self) void {
    printNode(self, self.root);
    std.debug.print("\n", .{});
}

fn printNode(self: *const Self, node_i: NodeID) void {
    switch (node_i) {
        .leaf => |leaf_i| {
            const node = self.leaves.get(leaf_i);
            std.debug.print("({d}: {d})", .{ node.offset, node.value });
        },
        .branch => |branch_i| {
            const node = self.branches.get(branch_i);
            std.debug.print("({c}{d}, ", .{ @as(u8, if (node.color == .black) 'b' else 'r'), node.offset });
            printNode(self, node.children[0]);
            std.debug.print(", ", .{});
            printNode(self, node.children[1]);
            std.debug.print(")", .{});
        },
    }
}

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

test "basic insert" {
    var tree: Self = .{
        .alloc = std.testing.allocator,
        .root = .{ .leaf = 0 },
    };
    try tree.leaves.append(tree.alloc, .{
        .offset = 1,
        .value = 0,
    });
    defer tree.deinit();

    try tree.insert(0, 1);
    var parent = tree.branches.get(tree.root.branch);
    var left = tree.leaves.get(parent.children[0].leaf);
    const right = tree.leaves.get(parent.children[1].leaf);
    try expectEqual(0, parent.offset);
    try expectEqual(0, left.offset);
    try expectEqual(1, right.offset);

    try tree.insert(2, 2);
    parent = tree.branches.get(tree.root.branch);
    left = tree.leaves.get(parent.children[0].leaf);
    const parent_right = tree.branches.get(parent.children[1].branch);
    const right_left = tree.leaves.get(parent_right.children[0].leaf);
    const right_right = tree.leaves.get(parent_right.children[1].leaf);

    try expectEqual(0, parent.offset);
    try expectEqual(0, left.offset);
    try expectEqual(1, parent_right.offset);
    try expectEqual(1, right_left.offset);
    try expectEqual(2, right_right.offset);
}

// TODO: Insert left, multiple rotation?
test "insertion with rotation" {
    var tree: Self = .{
        .alloc = std.testing.allocator,
        .root = .{ .leaf = 0 },
    };
    try tree.leaves.append(tree.alloc, .{
        .offset = 1,
        .value = 0,
    });
    defer tree.deinit();

    try tree.insert(2, 1);
    try tree.validate();
    var values = try tree.inorder(std.testing.allocator);
    try expectEqualSlices(u32, &.{ 0, 1 }, values);
    std.testing.allocator.free(values);

    try tree.insert(3, 2);
    try tree.validate();
    values = try tree.inorder(std.testing.allocator);
    try expectEqualSlices(u32, &.{ 0, 1, 2 }, values);
    std.testing.allocator.free(values);

    try tree.insert(4, 3);
    try tree.validate();
    values = try tree.inorder(std.testing.allocator);
    try expectEqualSlices(u32, &.{ 0, 1, 2, 3 }, values);
    std.testing.allocator.free(values);
}

// TODO: Fuzz testing?

test "validate" {
    const leaf: NodeID = .{ .leaf = 0 };
    var tree: Self = .{
        .alloc = std.testing.allocator,
        .root = leaf,
    };

    // Create tree manually to avoid balancing
    try tree.branches.append(tree.alloc, .{
        .offset = 0,
        .color = .black,
        .children = .{ leaf, leaf },
    });
    try tree.branches.append(tree.alloc, .{
        .offset = 1,
        .color = .black,
        .children = .{ leaf, .{ .branch = 2 } },
    });
    try tree.branches.append(tree.alloc, .{
        .offset = 2,
        .color = .red,
        .children = .{ leaf, leaf },
    });
    try tree.leaves.append(tree.alloc, .{
        .offset = 0,
        .value = 0,
    });
    defer tree.deinit();

    try tree.validate();

    var branch = tree.branches.get(0);
    branch.color = .red;
    tree.branches.set(0, branch);
    tree.root = .{ .branch = 0 };
    try expectError(error.RootIsRed, tree.validate());

    branch.color = .black;
    tree.branches.set(0, branch);
    try tree.validate();

    tree.root = .{ .branch = 1 };
    try tree.validate();

    tree.root = .{ .branch = 0 };
    branch.children[1] = .{ .branch = 1 };
    tree.branches.set(0, branch);
    try expectError(error.UnevenBlacks, tree.validate());

    branch = tree.branches.get(1);
    branch.color = .red;
    tree.branches.set(1, branch);
    try expectError(error.AdjacentReds, tree.validate());
}

test "inorder" {
    var tree: Self = .{
        .alloc = std.testing.allocator,
        .root = .{ .branch = 0 },
    };

    // Create tree manually to avoid potential bugs in insertion code
    try tree.branches.append(tree.alloc, .{
        .offset = 0,
        .color = .black,
        .children = .{ .{ .branch = 1 }, .{ .branch = 2 } },
    });
    try tree.branches.append(tree.alloc, .{
        .offset = 0,
        .color = .red,
        .children = .{ .{ .leaf = 0 }, .{ .leaf = 1 } },
    });
    try tree.branches.append(tree.alloc, .{
        .offset = 0,
        .color = .red,
        .children = .{ .{ .leaf = 2 }, .{ .leaf = 3 } },
    });
    try tree.leaves.append(tree.alloc, .{
        .offset = 0,
        .value = 1,
    });
    try tree.leaves.append(tree.alloc, .{
        .offset = 0,
        .value = 2,
    });
    try tree.leaves.append(tree.alloc, .{
        .offset = 0,
        .value = 3,
    });
    try tree.leaves.append(tree.alloc, .{
        .offset = 0,
        .value = 4,
    });
    defer tree.deinit();

    const values = try tree.inorder(std.testing.allocator);
    defer std.testing.allocator.free(values);
    try expectEqualSlices(u32, &.{ 1, 2, 3, 4 }, @ptrCast(values));
}
