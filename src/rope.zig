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
            const parent = self.parent orelse break;
            const right = parent.children[1] == self;
            const right_i: usize = @intFromBool(right);
            const left_i: usize = @intFromBool(!right);

            self.rotate(parent, left_i, right_i);
            if (self.parent) |grandparent| {
                const parent_right = grandparent.children[1] == parent;
                if (right == parent_right) {
                    self.rotate(grandparent, left_i, right_i);
                } else {
                    self.rotate(grandparent, right_i, left_i);
                }
            } else break;
        }
    }

    // Rotate around self
    fn rotate(self: *Node, parent: *Node, left_i: usize, right_i: usize) void {
        parent.children[right_i] = self.children[left_i];
        self.children[left_i] = parent;

        self.parent = parent.parent;
        parent.parent = self;

        if (right_i == 1) {
            self.offset += parent.offset + parent.str.len;
        } else {
            parent.offset -= self.offset + self.str.len;
        }
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
    var maybe_node: ?*Node = self.root;
    // Guaranteed to be defined as the loop will always run at least once
    var right: bool = undefined;

    while (maybe_node) |node| {
        if (relative_offset > node.offset and relative_offset < node.offset + node.str.len) {
            relative_offset -= node.offset;
            break;
        }

        right = relative_offset >= node.offset + node.str.len;
        if (right) {
            relative_offset -= node.offset + node.str.len;
        } else {
            node.offset += str.len;
        }

        std.debug.print("str: \"{s}\", offset: {d}, relative: {d}, going {s}\n", .{ node.str, node.offset, relative_offset, if (right) "right" else "left" });

        // std.debug.print("{any}\n", .{node});
        // const tmp = node;
        parent = node;
        maybe_node = node.children[@intFromBool(right)];
        // parent = tmp;
    }

    const new_node = try self.insertStr(maybe_node, parent, relative_offset, str);
    if (parent) |parent_node| {
        parent_node.children[@intFromBool(right)] = new_node;
        new_node.splay();
    }
    // If there's a parent, the new node will be splayed and therefore must be the root
    // If there's no parent, the new node must be the root and therefore splaying is not necessary
    self.root = new_node;
}

fn insertStr(self: *Self, maybe_node: ?*Node, parent: ?*Node, offset: usize, str: []const u8) !*Node {
    var new_node = try self.addNode(.{
        .parent = parent,
        .offset = 0,
        .str = str,
    });

    if (maybe_node) |node| {
        if (offset >= node.str.len or offset == 0) {
            std.debug.print("offset {d} out of bounds for string \"{s}\"\n", .{ offset, node.str });
            // TODO Delete this check or free node
            return error.OutOfBounds;
        }

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

        new_node.offset = offset + node.;
        new_node.children = .{ node, right_child };
    }

    return new_node;
}

pub fn inorder(self: *const Self, alloc: Allocator) ![][]const u8 {
    var values: std.ArrayList([]const u8) = .init(alloc);

    try self.inorderNode(self.root, &values);

    return values.toOwnedSlice();
}

fn inorderNode(self: *const Self, maybe_node: ?*Node, values: *std.ArrayList([]const u8)) !void {
    if (maybe_node) |node| {
        try self.inorderNode(node.children[0], values);
        try values.append(node.str);
        try self.inorderNode(node.children[1], values);
    }
}

pub fn print(self: *const Self) void {
    printNode(self.root);
    std.debug.print("\n", .{});
}

fn printNode(maybe_node: ?*Node) void {
    if (maybe_node) |node| {
        std.debug.print("({d} \"{s}\" ", .{ node.offset, node.str });
        printNode(node.children[0]);
        std.debug.print(" ", .{});
        printNode(node.children[1]);
        std.debug.print(")", .{});
    } else {
        std.debug.print("()", .{});
    }
}

pub fn testOffsets(self: *const Self, length: usize) !void {
    _ = try self.testOffset(self.root, length);
}

fn testOffset(self: *const Self, maybe_node: ?*const Node, length: usize) !usize {
    if (maybe_node) |node| {
        const left_length = try self.testOffset(node.children[0], node.offset);
        const right_length = try self.testOffset(node.children[1], length - node.offset - node.str.len);
        const actual_length = left_length + node.str.len + right_length;
        try expectEqual(length, actual_length);
        return actual_length;
    } else {
        try expectEqual(length, 0);
        return 0;
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

test "splay" {
    var rope: Self = try .init(testing.allocator, "22");
    defer rope.deinit();

    const left = try rope.addNode(.{
        .parent = rope.root,
        .offset = 0,
        .str = "1",
    });

    const right = try rope.addNode(.{
        .parent = rope.root,
        .offset = 0,
        .str = "333",
    });

    rope.root.offset = 1;
    rope.root.children = .{ left, right };

    try rope.expectInorder(&.{ "1", "22", "333" });
    try rope.testOffsets(6);

    const node = rope.root.children[1].?;
    node.splay();
    rope.root = node;

    try rope.expectInorder(&.{ "1", "22", "333" });
    try rope.testOffsets(6);
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
