// TODO:
// - Finish writing tests
// - Finalize API
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
    str: []const u8, // TODO: Replace with usize ptr and u32 len fields?
    next: ?u32 = null,
};

pub fn init(str: []const u8, alloc: Allocator) !Self {
    var self: Self = .{
        .root = .{ .leaf = 0 },
        .alloc = alloc,
    };

    try self.leaves.append(alloc, .{ .str = str });

    return self;
}

pub fn deinit(self: *Self) void {
    self.branches.deinit(self.alloc);
    self.leaves.deinit(self.alloc);
}

inline fn addLeaf(self: *Self, leaf: Leaf) !NodeID {
    const node_i: NodeID = .{ .leaf = @intCast(self.leaves.len) };
    try self.leaves.append(self.alloc, leaf);
    return node_i;
}

inline fn addBranch(self: *Self, branch: Branch) !NodeID {
    const node_i: NodeID = .{ .branch = @intCast(self.branches.len) };
    try self.branches.append(self.alloc, branch);
    return node_i;
}

// TODO: Make this function (and the ones it calls) atomic? i.e. it either works or doesn't change tree
pub fn insert(self: *Self, offset: u32, str: []const u8) !void {
    var node_i = self.root;
    var branches = self.branches.slice();
    var offsets = branches.items(.offset);
    // The length of everything to the left of the current node
    var relative_offset = offset;
    var parent: ?u32 = null;
    var right: bool = undefined;

    while (true) {
        switch (node_i) {
            .branch => |branch_i| {
                const branch = branches.get(branch_i);
                parent = branch_i;
                right = relative_offset >= branch.offset;
                node_i = branch.children[@intFromBool(right)];
                if (right) {
                    // Update to maintain relativity
                    relative_offset -= branch.offset;
                } else {
                    // Relative offset of branch increases since we insert left
                    offsets[branch_i] += @intCast(str.len);
                }
            },
            .leaf => |leaf_i| {
                const branch_i = try self.insertLeaf(leaf_i, parent, relative_offset, str);

                if (std.meta.eql(node_i, self.root)) {
                    self.root = branch_i;
                    var colors = self.branches.items(.color);
                    colors[branch_i.branch] = .black;
                }

                if (parent) |parent_i| {
                    var childrens = self.branches.items(.children);
                    // right only gets used iff there is a parent, which guarantees that it's defined
                    childrens[parent_i][@intFromBool(right)] = branch_i;
                }

                self.rebalance(branch_i.branch);
                break;
            },
        }
    }
}

fn insertLeaf(self: *Self, leaf_i: u32, parent: ?u32, offset: u32, str: []const u8) !NodeID {
    var branch_i: NodeID = undefined;
    var leaf = self.leaves.get(leaf_i);
    const str_len: u32 = @intCast(str.len);

    if (offset > @as(u32, @intCast(leaf.str.len))) {
        return error.OutOfBounds;
    }

    // Insert new leaf
    const new_leaf_i = try self.addLeaf(.{ .str = str });

    const at_start = offset == 0;
    if (at_start or offset == leaf.str.len) {
        // Single branch and with existing and new leaf as children
        var branch: Branch = .{
            .color = .red,
            .offset = if (at_start) str_len else @intCast(leaf.str.len),
            .parent = parent,
        };
        branch.children[@intFromBool(at_start)] = .{ .leaf = leaf_i };
        branch.children[@intFromBool(!at_start)] = new_leaf_i;

        branch_i = try self.addBranch(branch);
    } else {
        // Nested branches with two existing leaves and new leaf

        // New leaf, left half of original
        const leaf_start_i = try self.addLeaf(.{
            .str = leaf.str[0..offset],
        });

        // Original leaf, update to be right half
        leaf.str = leaf.str[offset..];
        self.leaves.set(leaf_i, leaf);

        const child_branch_i = try self.addBranch(.{
            .color = .red, // We want this to be rebalanced // TODO: Just recolor manually?
            .offset = str_len,
            .parent = @as(u32, @intCast(self.branches.len)) + 1,
            .children = .{ new_leaf_i, .{ .leaf = leaf_i } },
        });

        // TODO: Direction? Do I care? Does balancing still work?
        branch_i = try self.addBranch(.{
            .color = .red,
            .offset = offset,
            .parent = parent,
            .children = .{ leaf_start_i, child_branch_i },
        });
    }

    return branch_i;
}

// Traverse up the tree and check colors/rebalance
fn rebalance(self: *Self, branch_i: u32) void {
    var branches = self.branches.slice();
    var colors = branches.items(.color);
    var offsets = branches.items(.offset);
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
            const left_i = @intFromBool(!right);
            const uncle_i = children[left_i];

            switch (uncle_i) {
                .branch => |uncle_branch_i| { // Recolor
                    colors[parent_i] = .black;
                    colors[uncle_branch_i] = .black;
                },
                .leaf => |uncle_leaf_i| { // Rotate
                    childrens[grandparent_i][right_i] = childrens[parent_i][left_i];
                    childrens[parent_i][left_i] = .{ .branch = grandparent_i };
                    parents[parent_i] = parents[grandparent_i];
                    parents[grandparent_i] = parent_i;

                    const uncle = self.leaves.get(uncle_leaf_i);
                    offsets[parent_i] += @intCast(uncle.str.len);

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
pub fn inorder(self: *const Self, alloc: Allocator) ![][]const u8 {
    var values: std.ArrayList([]const u8) = .init(alloc);

    try self.inorderNode(self.root, &values);

    return try values.toOwnedSlice();
}

fn inorderNode(self: *const Self, node_i: NodeID, values: *std.ArrayList([]const u8)) !void {
    switch (node_i) {
        .leaf => |leaf_i| {
            const leaf_strs = self.leaves.items(.str);
            try values.append(leaf_strs[leaf_i]);
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
            std.debug.print("\"{s}\"", .{node.str});
        },
        .branch => |branch_i| {
            const node = self.branches.get(branch_i);
            std.debug.print("({c}{d} ", .{ @as(u8, if (node.color == .black) 'b' else 'r'), node.offset });
            printNode(self, node.children[0]);
            std.debug.print(" ", .{});
            printNode(self, node.children[1]);
            std.debug.print(")", .{});
        },
    }
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualSlices = testing.expectEqualSlices;

fn expectInorder(self: *const Self, expected: []const []const u8) !void {
    const actual = try self.inorder(testing.allocator);
    try expectEqual(expected.len, actual.len);
    for (0..actual.len) |i| {
        try expectEqualSlices(u8, expected[i], actual[i]);
    }
    testing.allocator.free(actual);
}

test "basic insert" {
    var tree: Self = try .init("0", testing.allocator);
    defer tree.deinit();

    try tree.insert(0, "1");
    try tree.validate();
    var parent = tree.branches.get(tree.root.branch);
    try expectEqual(1, parent.offset);

    try tree.insert(2, "2");
    try tree.validate();
    parent = tree.branches.get(tree.root.branch);
    const parent_right = tree.branches.get(parent.children[1].branch);

    try expectEqual(1, parent.offset);
    try expectEqual(1, parent_right.offset);

    try tree.expectInorder(&.{ "1", "0", "2" });
}

// TODO: Insert left, multiple rotation?
test "insertion with rotation" {
    var tree: Self = try .init("0", testing.allocator);
    defer tree.deinit();

    try tree.insert(1, "1");
    try tree.validate();
    try tree.expectInorder(&.{ "0", "1" });

    try tree.insert(2, "2");
    try tree.validate();
    try tree.expectInorder(&.{ "0", "1", "2" });

    try tree.insert(3, "3");
    try tree.validate();
    try tree.expectInorder(&.{ "0", "1", "2", "3" });
}

test "insertion in middle of string" {
    var tree: Self = try .init("Hello world", testing.allocator);
    defer tree.deinit();

    tree.print();
    try tree.insert(5, ",");
    tree.print();
    try tree.validate();
    try tree.expectInorder(&.{ "Hello", ",", " world" });

    try tree.insert(12, "!!");
    tree.print();
    try tree.validate();
    try tree.expectInorder(&.{ "Hello", ",", " world", "!!" });

    try tree.insert(2, "llo he");
    tree.print();
    try tree.validate();
    try tree.expectInorder(&.{ "He", "llo he", "llo", ",", " world", "!!" });
}

// TODO: Fuzz testing?

test "validate" {
    const leaf: NodeID = .{ .leaf = 0 };
    var tree: Self = .{
        .alloc = testing.allocator,
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
    try tree.leaves.append(tree.alloc, .{ .str = "" });
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
        .alloc = testing.allocator,
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
        .str = "1",
    });
    try tree.leaves.append(tree.alloc, .{
        .str = "2",
    });
    try tree.leaves.append(tree.alloc, .{
        .str = "3",
    });
    try tree.leaves.append(tree.alloc, .{
        .str = "4",
    });
    defer tree.deinit();

    try tree.expectInorder(&.{ "1", "2", "3", "4" });
}
