const std = @import("std");
const Allocator = std.mem.Allocator;
const MemoryPool = std.heap.MemoryPool;

const Self = @This();

root: *Node,
nodes: MemoryPool(Node),

const Node = struct {
    parent: ?*Node = null,
    children: [2]?*Node = .{ null, null },
    offset: usize,
    str: []const u8,

    pub fn splay(self: *Node) void {
        while (true) {
            const parent = self.parent orelse return;
            const right = parent.children[1] == self;
            const right_i: usize = @intFromBool(right);
            const left_i: usize = @intFromBool(!right);

            if (parent.parent) |grandparent| {
                const parent_right = grandparent.children[1] == parent;
                if (right == parent_right) {
                    self.rotateZigZig(parent, grandparent, left_i, right_i);
                } else {
                    self.rotateZigZag(parent, grandparent, left_i, right_i);
                }
            } else {
                self.rotateZig(parent, left_i, right_i);
                break;
            }
        }
    }

    fn rotateZig(self: *Node, parent: *Node, left_i: usize, right_i: usize) void {
        parent.children[left_i] = self.children[right_i];
        self.children[right_i] = parent;

        self.parent = parent.parent;
        parent.parent = self;

        parent.offset -= self.offset + self.str.len;
    }

    fn rotateZigZig(self: *Node, parent: *Node, grandparent: *Node, left_i: usize, right_i: usize) void {
        grandparent.children[left_i] = parent.children[right_i];
        parent.children[right_i] = grandparent;

        parent.children[left_i] = self.children[right_i];
        self.children[right_i] = parent;

        self.parent = grandparent.parent;
        parent.parent = self;
        grandparent.parent = parent;

        grandparent.offset -= parent.offset + parent.str.len;
        parent.offset -= self.offset + self.str.len;
    }

    fn rotateZigZag(self: *Node, parent: *Node, grandparent: *Node, left_i: usize, right_i: usize) void {
        parent.children[right_i] = self.children[left_i];
        grandparent.children[left_i] = self.children[right_i];

        self.children[left_i] = parent;
        self.children[right_i] = grandparent;

        self.parent = grandparent.parent;
        parent.parent = self;
        grandparent.parent = self;

        self.offset += parent.offset + parent.str.len;
        grandparent.offset -= self.offset + self.str.len;
    }
};

pub fn init(alloc: Allocator, str: []const u8) !Self {
    var self: Self = .{
        .root = undefined,
        .nodes = .init(alloc),
    };

    self.root = try self.addNode(.{ .offset = 0, .str = str });

    return self;
}

pub fn deinit(self: *Self) void {
    self.nodes.deinit();
}

inline fn addNode(self: *Self, node: Node) !*Node {
    const node_ptr = try self.nodes.create();
    node_ptr.* = node;
    return node_ptr;
}

pub fn insert(self: *Self, offset: usize, str: []const u8) !void {
    // The length of everything to the left of the current node
    var relative_offset = offset;
    var parent: ?*Node = null;
    var node: *Node = self.root;
    // Guaranteed to be defined as the loop will always run at least once
    var right: bool = undefined;

    while (true) {
        parent = node;
        right = relative_offset >= node.offset;
        std.debug.print("str: \"{s}\", offset: {d}, going {s}\n", .{ node.str, node.offset, if (right) "right" else "left" });
        node = node.children[@intFromBool(right)] orelse break;

        if (right) {
            relative_offset -= node.offset + node.str.len;
        } else {
            node.offset += str.len;
        }
    }

    const new_node = try self.insertStr(node, parent, relative_offset, str);
    if (parent) |parent_node| {
        parent_node.children[@intFromBool(right)] = new_node;
        new_node.splay();
    } else {
        // If there's no parent, the new node must be the root
        // Therefore, splaying is not necessary
        self.root = new_node;
    }
}

fn insertStr(self: *Self, node: *Node, parent: ?*Node, offset: usize, str: []const u8) !*Node {
    if (offset > node.str.len) return error.OutOfBounds;

    var new_node = try self.addNode(.{
        .parent = parent,
        .offset = offset,
        .str = str,
    });

    const at_end = offset == node.str.len;
    if (offset == 0 or at_end) {
        new_node.children[@intFromBool(at_end)] = node;

        node.parent = new_node;
        node.offset = 0;
    } else {
        const right_child = try self.addNode(.{
            .parent = new_node,
            .children = .{ null, node.children[1] },
            .offset = 0,
            .str = node.str[offset..],
        });

        // Reuse existing node as left child
        node.parent = new_node;
        node.children[1] = null;
        node.offset = 0;
        node.str = node.str[0..offset];

        new_node.children = .{ node, right_child };
    }

    return new_node;
}

pub fn inorder(self: *const Self, alloc: Allocator) ![][]const u8 {
    var values: std.ArrayList([]const u8) = .init(alloc);

    try self.inorderNode(self.root, &values);

    return try values.toOwnedSlice();
}

fn inorderNode(self: *const Self, maybe_node: ?*Node, values: *std.ArrayList([]const u8)) !void {
    if (maybe_node) |node| {
        try self.inorderNode(node.children[0], values);
        try values.append(node.str);
        try self.inorderNode(node.children[1], values);
    }
}

pub fn print(self: *const Self) void {
    printNode(self, self.root);
    std.debug.print("\n", .{});
}

fn printNode(self: *const Self, maybe_node: ?*Node) void {
    if (maybe_node) |node| {
        std.debug.print(" ({d} \"{s}\"", .{ node.offset, node.str });
        self.printNode(node.children[0]);
        self.printNode(node.children[1]);
        std.debug.print(")", .{});
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

test "basic insertion" {
    var rope: Self = try .init(testing.allocator, "Hello");
    defer rope.deinit();

    rope.print();
    try rope.insert(5, ",");
    rope.print();
    try rope.expectInorder(&.{ "Hello", "," });

    try rope.insert(6, "world");
    rope.print();
    try rope.expectInorder(&.{ "Hello", ",", "world" });

    try rope.insert(7, " ");
    rope.print();
    try rope.expectInorder(&.{ "Hello", ",", " ", "world" });

    try rope.insert(12, "!");
    rope.print();
    try rope.expectInorder(&.{ "Hello", ",", " ", "world", "!" });
}
