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

    pub const empty: Node = .{ .offset = 0, .str = "" };

    // Does not update root. This must be done after calling
    pub fn splay(self: *Node) void {
        while (self.parent) |parent| self.rotate(parent);
    }

    // Rotate around self
    fn rotate(self: *Node, parent: *Node) void {
        const right = parent.children[1] == self;
        const right_i: usize = @intFromBool(right);
        const left_i: usize = @intFromBool(!right);

        if (self.children[left_i]) |child| child.parent = parent;
        parent.children[right_i] = self.children[left_i];
        self.children[left_i] = parent;

        if (parent.parent) |grandparent| {
            const parent_right = grandparent.children[1] == parent;
            grandparent.children[@intFromBool(parent_right)] = self;
        }
        self.parent = parent.parent;
        parent.parent = self;

        if (right) {
            self.offset += parent.offset + parent.str.len;
        } else {
            parent.offset -= self.offset + self.str.len;
        }
    }

    pub fn next(self: *Node) ?*Node {
        return self.move(true);
    }

    pub fn prev(self: *Node) ?*Node {
        return self.move(false);
    }

    inline fn move(self: *Node, right: bool) ?*Node {
        const right_i: usize = @intFromBool(right);
        const left_i: usize = @intFromBool(!right);
        var node = self;

        if (node.children[right_i]) |right_child| {
            node = right_child;
            while (node.children[left_i]) |left_child| : (node = left_child) {}
        } else {
            while (node.parent) |parent| {
                // If node is a left child, parent is the successor
                defer node = parent;
                if (parent.children[left_i] == node) break;
            } else return null;
        }

        return node;
    }

    // Find node with maximum offset
    pub fn maximum(self: *Node) *Node {
        var node = self;
        return while (node.children[1]) |child| : (node = child) {} else node;
    }

    // Joins left and right subtrees. Returns the root of the new subtree
    pub fn join(left: ?*Node, right: ?*Node) ?*Node {
        if (left == null or right == null) {
            return left orelse right;
        } else {
            left.maximum().splay(); // This guarantees a null right child
            std.debug.assert(left.children[1] == null);
            left.children[1] = right;
            return left;
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

        parent = node;
        maybe_node = node.children[@intFromBool(right)];
    }

    const new_node = try self.insertNode(maybe_node, parent, relative_offset, str);
    if (parent) |parent_node| {
        // Right is guaranteed to be defined here as the loop has to run at least once for the parent to be non-null
        parent_node.children[@intFromBool(right)] = new_node;
        new_node.splay();
    }
    // If there's a parent, the new node will be splayed and therefore must be the root
    // If there's no parent, the new node must be the root and therefore splaying is not necessary
    self.root = new_node;
}

fn insertNode(self: *Self, maybe_node: ?*Node, parent: ?*Node, offset: usize, str: []const u8) !*Node {
    var new_node = try self.addNode(.{
        .parent = parent,
        .offset = 0,
        .str = str,
    });

    if (maybe_node) |node| {
        // Must insert in middle of string
        // These cases are handled by the insert function
        std.debug.assert(offset > 0 and offset < node.str.len);

        const right_child = try self.addNode(.{
            .parent = new_node,
            .children = .{ null, node.children[1] },
            .offset = 0,
            .str = node.str[offset..],
        });

        // Reuse existing node as left child
        node.parent = new_node;
        node.children[1] = null;
        node.str = node.str[0..offset];

        new_node.offset = offset + node.offset;
        new_node.children = .{ node, right_child };
    }

    return new_node;
}

pub fn delete(self: *Self, from: usize, to_or_end: ?usize) !void {
    const left, var deleted = try self.split(from);

    if (to_or_end) |to| {
        std.debug.assert(to > from);

        self.root = deleted orelse unreachable; // TODO
        deleted, const right = try self.split(to);
        self.root = Node.join(left, right) orelse try self.addNode(.empty); // TODO
    } else {
        self.root = left orelse try self.addNode(.empty); // TODO: Should root be optional? For new buffers with no content or where all content has been deleted
    }

    // TODO: Return a "change" which holds a reference to the deleted subtree
}

// Splits rope at offset. Returns left and right subtrees. Does not update root
fn split(self: *Self, offset: usize) ![2]?*Node {
    const node = self.find(offset) orelse return error.OutOfBounds;
    node.splay();
    self.root = node;

    const relative_offset = offset - node.offset;
    const at_end = relative_offset == node.str.len;

    std.debug.assert(relative_offset <= node.str.len);
    if (relative_offset == 0 or at_end) {
        const maybe_child = node.children[@intFromBool(at_end)];
        if (maybe_child) |child| {
            node.children[@intFromBool(at_end)] = null;
            child.parent = null;
        }
        return if (at_end) .{ node, maybe_child } else .{ maybe_child, node };
    } else {
        // New node becomes left subtree
        var new_node = try self.addNode(.{
            .offset = 0,
            .str = node.str[0..relative_offset],
        });
        new_node.children[0] = node.children[0];
        // Original node becomes right subtree
        node.children[0] = null;
        node.str = node.str[relative_offset..];

        return .{ new_node, node };
    }
}

// Find the node containing offset, if there is one
fn find(self: *const Self, offset: usize) ?*Node {
    var maybe_node: ?*Node = self.root;
    var relative_offset = offset;

    while (maybe_node) |node| {
        if (relative_offset >= node.offset and relative_offset <= node.offset + node.str.len) return node;

        const right = relative_offset >= node.offset + node.str.len;
        if (right) relative_offset -= node.offset + node.str.len;
        maybe_node = node.children[@intFromBool(right)];
    }

    return null;
}

pub fn inorder(node: *const Node, alloc: Allocator) ![][]const u8 {
    var values: std.ArrayList([]const u8) = .init(alloc);
    errdefer values.deinit();

    try inorderNode(node, &values);

    return values.toOwnedSlice();
}

fn inorderNode(maybe_node: ?*const Node, values: *std.ArrayList([]const u8)) !void {
    if (maybe_node) |node| {
        try inorderNode(node.children[0], values);
        try values.append(node.str);
        try inorderNode(node.children[1], values);
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

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualSlices = testing.expectEqualSlices;

pub fn validate(self: *const Self, expected: []const []const u8) !void {
    try self.expectAcyclic();
    try self.expectInorder(expected);
    var length: usize = 0;
    for (expected) |str| length += str.len;
    try self.expectOffsets(length);
    try self.expectLinked();
}

pub fn expectAcyclic(self: *const Self) !void {
    var map: std.AutoHashMap(*const Node, void) = .init(testing.allocator);
    defer map.deinit();

    try expectAcyclicNode(self.root.children[0], self.root, &map);
    try expectAcyclicNode(self.root.children[1], self.root, &map);
}

fn expectAcyclicNode(maybe_node: ?*const Node, parent: *const Node, map: *std.AutoHashMap(*const Node, void)) !void {
    if (maybe_node) |node| {
        if (map.contains(node)) {
            std.debug.print("Found cycle: node \"{s}\" ", .{node.str});
            if (node.parent) |actual_parent| std.debug.print("with parent \"{s}\" ", .{actual_parent.str});
            std.debug.print("pointed to by \"{s}\"\n", .{parent.str});
            return error.FoundCycle;
        }

        try map.put(node, {});
        try expectAcyclicNode(node.children[0], node, map);
        try expectAcyclicNode(node.children[1], node, map);
    }
}

pub fn expectInorder(self: *const Self, expected: []const []const u8) !void {
    return expectInorderNode(self.root, expected);
}

fn expectInorderNode(node: *const Node, expected: []const []const u8) !void {
    const actual = try inorder(node, testing.allocator);
    defer testing.allocator.free(actual);
    errdefer std.debug.print("Inorder slices are different:\n  expected: {any}\n  actual: {any}\n", .{ expected, actual });

    try expectEqual(expected.len, actual.len);
    for (0..actual.len) |i| {
        try expectEqualSlices(u8, expected[i], actual[i]);
    }
}

pub fn expectOffsets(self: *const Self, length: usize) !void {
    _ = try self.expectOffsetsNode(self.root, length);
}

fn expectOffsetsNode(self: *const Self, maybe_node: ?*const Node, length: usize) !usize {
    if (maybe_node) |node| {
        const left_length = try self.expectOffsetsNode(node.children[0], node.offset);
        const right_length = try self.expectOffsetsNode(node.children[1], length - node.offset - node.str.len);
        const actual_length = left_length + node.str.len + right_length;
        try expectEqual(length, actual_length);
        return actual_length;
    } else {
        try expectEqual(length, 0);
        return 0;
    }
}

pub fn expectLinked(self: *const Self) !void {
    try expectEqual(null, self.root.parent);
    return expectLinkedNode(self.root);
}

fn expectLinkedNode(node: *const Node) !void {
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            expectEqual(node, child.parent) catch |err| {
                std.debug.print("Malformed link between node \"{s}\" and child \"{s}\"\n", .{ node.str, child.str });
                return err;
            };
            expect(node != child) catch |err| {
                std.debug.print("Node \"{s}\" child refers to itself\n", .{node.str});
                return err;
            };
            try expectLinkedNode(child);
        }
    }
}

test "inorder" {
    // ("2" ("1" () ()) ("3" ("4" () ("5" () ()))))
    var rope: Self = try .init(testing.allocator, "2");
    defer rope.deinit();

    const one = try rope.addNode(.{
        .parent = rope.root,
        .offset = 0,
        .str = "1",
    });

    const five = try rope.addNode(.{
        .parent = rope.root,
        .offset = 2,
        .str = "5",
    });

    const three = try rope.addNode(.{
        .parent = five,
        .offset = 0,
        .str = "3",
    });

    const four = try rope.addNode(.{
        .parent = three,
        .offset = 0,
        .str = "4",
    });

    rope.root.children = .{ one, five };
    rope.root.offset = 1;
    five.children[0] = three;
    three.children[1] = four;

    try rope.validate(&.{ "1", "2", "3", "4", "5" });

    var node: ?*Node = one;
    node = node.?.next();
    try expectEqual(rope.root, node);
    node = node.?.next();
    try expectEqual(three, node);
    node = node.?.next();
    try expectEqual(four, node);
    node = node.?.next();
    try expectEqual(five, node);

    node = node.?.prev();
    try expectEqual(four, node);
    node = node.?.prev();
    try expectEqual(three, node);
    node = node.?.prev();
    try expectEqual(rope.root, node);
    node = node.?.prev();
    try expectEqual(one, node);
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

    try rope.validate(&.{ "1", "22", "333" });

    const node = rope.root.children[1].?;
    node.splay();
    rope.root = node;

    try rope.validate(&.{ "1", "22", "333" });
}

// TODO: More splay tests

test "basic insertion" {
    var rope: Self = try .init(testing.allocator, "Hello");
    defer rope.deinit();

    try rope.insert(5, ",");
    try rope.validate(&.{ "Hello", "," });

    try rope.insert(6, "world");
    try rope.validate(&.{ "Hello", ",", "world" });

    try rope.insert(6, " ");
    try rope.validate(&.{ "Hello", ",", " ", "world" });

    try rope.insert(12, "!");
    try rope.validate(&.{ "Hello", ",", " ", "world", "!" });
}

test "advanced insertion" {
    var rope: Self = try .init(testing.allocator, "Hlord");
    defer rope.deinit();

    try rope.insert(1, "el");
    try rope.validate(&.{ "H", "el", "lord" });

    try rope.insert(5, ", ");
    try rope.validate(&.{ "H", "el", "lo", ", ", "rd" });

    try rope.insert(7, "wo");
    try rope.validate(&.{ "H", "el", "lo", ", ", "wo", "rd" });

    try rope.insert(10, "l");
    try rope.validate(&.{ "H", "el", "lo", ", ", "wo", "r", "l", "d" });

    try rope.insert(12, "!");
    try rope.validate(&.{ "H", "el", "lo", ", ", "wo", "r", "l", "d", "!" });
}

fn makeRope1() !Self {
    var rope: Self = try .init(testing.allocator, "Hlord");

    try rope.insert(1, "el");
    try rope.insert(5, ", ");
    try rope.insert(7, "wo");
    try rope.insert(10, "l");
    try rope.validate(&.{ "H", "el", "lo", ", ", "wo", "r", "l", "d" });

    return rope;
}

test "split middle" {
    var rope: Self = try makeRope1();
    defer rope.deinit();

    const left, const right = try rope.split(6);
    try expect(left != null);
    try expect(right != null);

    try expectInorderNode(left.?, &.{ "H", "el", "lo", "," });
    try expectInorderNode(right.?, &.{ " ", "wo", "r", "l", "d" });
}

test "split left" {
    var rope: Self = try makeRope1();
    defer rope.deinit();

    const left, const right = try rope.split(5);
    try expect(left != null);
    try expect(right != null);

    try expectInorderNode(left.?, &.{ "H", "el", "lo" });
    try expectInorderNode(right.?, &.{ ", ", "wo", "r", "l", "d" });
}

test "split right" {
    var rope: Self = try makeRope1();
    defer rope.deinit();

    const left, const right = try rope.split(7);
    try expect(left != null);
    try expect(right != null);

    try expectInorderNode(left.?, &.{ "H", "el", "lo", ", " });
    try expectInorderNode(right.?, &.{ "wo", "r", "l", "d" });
}

test "split start" {
    var rope: Self = try makeRope1();
    defer rope.deinit();

    const left, const right = try rope.split(0);
    try expect(left == null);
    try expect(right != null);

    try expectInorderNode(right.?, &.{ "H", "el", "lo", ", ", "wo", "r", "l", "d" });
}

test "split end" {
    var rope: Self = try makeRope1();
    defer rope.deinit();

    const left, const right = try rope.split(1);
    try expect(left != null);
    try expect(right != null);

    try expectInorderNode(left.?, &.{"H"});
    try expectInorderNode(right.?, &.{ "el", "lo", ", ", "wo", "r", "l", "d" });
}
