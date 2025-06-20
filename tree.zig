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
};

const Branch = struct {
    color: enum { black, red } = .black,
    offset: u32,
    parent: ?u32 = null,
    children: [2]NodeID = undefined, // left, right
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
                    .offset = if (right) leaf_offset else offset,
                    .parent = parent,
                };
                branch.children[@intFromBool(right)] = .{ .leaf = i };
                branch.children[@intFromBool(!right)] = .{ .leaf = leaf_i };

                try self.branches.append(self.alloc, branch);
                const branch_i: NodeID = .{ .branch = @intCast(self.branches.len - 1) };

                if (std.meta.eql(node_i, self.root)) self.root = branch_i;
                if (parent) |parent_i| {
                    var parent_node = self.branches.get(parent_i);
                    parent_node.children[@intFromBool(right)] = branch_i;
                    self.branches.set(parent_i, parent_node);
                }
                break;
            },
        }
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
