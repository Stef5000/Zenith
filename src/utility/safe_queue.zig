const std = @import("std");

/// A thread-safe Multi-Producer, Single-Consumer queue.
pub fn SafeQueue(comptime T: type) type {
    return struct {
        mutex: std.Thread.Mutex,
        // STRICT: Use Unmanaged
        items: std.ArrayList(T),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .mutex = .{},
                // STRICT: Initialize with empty struct literal
                .items = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            // STRICT: Pass allocator to deinit
            self.items.deinit(self.allocator);
        }

        /// Thread-safe append
        pub fn push(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            // STRICT: Pass allocator to append
            try self.items.append(self.allocator, item);
        }

        /// Move all items to a consumer buffer (clearing the queue).
        pub fn consume(self: *Self, out_list: *std.ArrayList(T)) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) return;

            // STRICT: Pass allocator to appendSlice
            try out_list.appendSlice(self.allocator, self.items.items);

            // STRICT: clearRetainingCapacity doesn't need allocator, but modifying items does
            self.items.clearRetainingCapacity();
        }
    };
}
