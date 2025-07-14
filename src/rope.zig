const std = @import("std");
const Allocator = std.mem.Allocator;
const MemoryPool = std.heap.MemoryPool;

const Self = @This();

root: *Node,
nodes: MemoryPool(Node),

const Node = struct {
    parent: ?*Node,
    children: [2]?*Node,
    offset: usize,
    str: []const u8,

    pub fn splay(self: *@This()) void {
        while (true) {
            const parent = self.parent orelse return;
            const right = parent.children[1] == self;

            if (parent.parent) |grandparent| {
                // Double rotation
                const parent_right = grandparent.children[1] == parent;
                const right_i: usize = @intFromBool(right);
                const left_i: usize = @intFromBool(!right);

                if (right == parent_right) {
                    // Normal double rotation
                    grandparent.children[left_i] = parent.children[right_i];
                    parent.children[right_i] = grandparent;

                    parent.children[left_i] = self.children[right_i];
                    self.children[right_i] = parent;

                    self.parent = grandparent.parent;
                    parent.parent = self;
                    grandparent.parent = parent;

                    // TODO: offsets
                } else {
                    // Zig-zag rotation
                    parent.children[right_i] = self.children[left_i];
                    grandparent.children[left_i] = self.children[right_i];

                    self.children[left_i] = parent;
                    self.children[right_i] = grandparent;

                    self.parent = grandparent.parent;
                    parent.parent = &self.branch;
                    grandparent.parent = &self.branch;

                    // TODO: offsets
                }
            } else {
                // Single rotation
                parent.children[left_i] = self.children[right_i];
                self.children[right_i] = parent;

                self.parent = parent.parent;
                parent.parent = self;

                // TODO: offsets
            }
        }
    }
};

pub fn init(alloc: Allocator, str: []const u8) !Self {
    return undefined;
}
