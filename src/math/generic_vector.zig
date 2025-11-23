const std = @import("std");
const root = @import("math.zig");
const math = std.math;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const panic = std.debug.panic;

pub const Vec2 = GenericVector(2, f32);
pub const Vec2_f64 = GenericVector(2, f64);
pub const Vec2_i32 = GenericVector(2, i32);
pub const Vec2_usize = GenericVector(2, usize);

pub const Vec3 = GenericVector(3, f32);
pub const Vec3_f64 = GenericVector(3, f64);
pub const Vec3_i32 = GenericVector(3, i32);
pub const Vec3_usize = GenericVector(3, usize);

pub const Vec4 = GenericVector(4, f32);
pub const Vec4_f64 = GenericVector(4, f64);
pub const Vec4_i32 = GenericVector(4, i32);
pub const Vec4_usize = GenericVector(4, usize);

/// A generic vector.
pub fn GenericVector(comptime dimensions: comptime_int, comptime T: type) type {
    if (@typeInfo(T) != .float and @typeInfo(T) != .int) {
        @compileError("Vectors not implemented for " ++ @typeName(T));
    }

    if (dimensions < 2 or dimensions > 4) {
        @compileError("Dimensions must be 2, 3 or 4!");
    }

    return extern struct {
        const Self = @This();
        const Data = @Vector(dimensions, T);

        data: Data,

        pub const Component = switch (dimensions) {
            2 => enum { x, y },
            3 => enum { x, y, z },
            4 => enum { x, y, z, w },
            else => unreachable,
        };

        pub const DimensionImpl = switch (dimensions) {
            2 => struct {
                /// Construct new vector.
                pub inline fn new(vx: T, vy: T) Self {
                    return .{ .data = [2]T{ vx, vy } };
                }

                /// Rotate vector by angle (in degrees)
                pub fn rotate(self: Self, angle_in_degrees: T) Self {
                    const sin_theta = @sin(root.toRadians(angle_in_degrees));
                    const cos_theta = @cos(root.toRadians(angle_in_degrees));
                    return .{ .data = [2]T{
                        cos_theta * self.x() - sin_theta * self.y(),
                        sin_theta * self.x() + cos_theta * self.y(),
                    } };
                }

                pub inline fn toVec3(self: Self, vz: T) GenericVector(3, T) {
                    return GenericVector(3, T).fromVec2(self, vz);
                }

                pub inline fn toVec4(self: Self, vz: T, vw: T) GenericVector(4, T) {
                    return GenericVector(4, T).fromVec2(self, vz, vw);
                }

                pub inline fn fromVec3(vec3: GenericVector(3, T)) Self {
                    return Self.new(vec3.x(), vec3.y());
                }

                pub inline fn fromVec4(vec4: GenericVector(4, T)) Self {
                    return Self.new(vec4.x(), vec4.y());
                }
            },
            3 => struct {
                /// Construct new vector.
                pub inline fn new(vx: T, vy: T, vz: T) Self {
                    return .{ .data = [3]T{ vx, vy, vz } };
                }

                pub inline fn z(self: Self) T {
                    return self.data[2];
                }

                pub inline fn zMut(self: *Self) *T {
                    return &self.data[2];
                }

                /// Shorthand for (0, 0, 1).
                pub fn forward() Self {
                    return Self.new(0, 0, 1);
                }

                /// Shorthand for (0, 0, -1).
                pub fn back() Self {
                    return Self.forward().negate();
                }

                /// Construct the cross product (as vector) from two vectors.
                pub fn cross(first_vector: Self, second_vector: Self) Self {
                    const x1 = first_vector.x();
                    const y1 = first_vector.y();
                    const z1 = first_vector.z();

                    const x2 = second_vector.x();
                    const y2 = second_vector.y();
                    const z2 = second_vector.z();

                    const result_x = (y1 * z2) - (z1 * y2);
                    const result_y = (z1 * x2) - (x1 * z2);
                    const result_z = (x1 * y2) - (y1 * x2);
                    return Self.new(result_x, result_y, result_z);
                }

                pub inline fn toVec2(self: Self) GenericVector(2, T) {
                    return GenericVector(2, T).fromVec3(self);
                }

                pub inline fn toVec4(self: Self, vw: T) GenericVector(4, T) {
                    return GenericVector(4, T).fromVec3(self, vw);
                }

                pub inline fn fromVec2(vec2: GenericVector(2, T), vz: T) Self {
                    return Self.new(vec2.x(), vec2.y(), vz);
                }

                pub inline fn fromVec4(vec4: GenericVector(4, T)) Self {
                    return Self.new(vec4.x(), vec4.y(), vec4.z());
                }
            },
            4 => struct {
                /// Construct new vector.
                pub inline fn new(vx: T, vy: T, vz: T, vw: T) Self {
                    return .{ .data = [4]T{ vx, vy, vz, vw } };
                }

                /// Shorthand for (0, 0, 1, 0).
                pub fn forward() Self {
                    return Self.new(0, 0, 1, 0);
                }

                /// Shorthand for (0, 0, -1, 0).
                pub fn back() Self {
                    return Self.forward().negate();
                }

                pub inline fn z(self: Self) T {
                    return self.data[2];
                }

                pub inline fn w(self: Self) T {
                    return self.data[3];
                }

                pub inline fn zMut(self: *Self) *T {
                    return &self.data[2];
                }

                pub inline fn wMut(self: *Self) *T {
                    return &self.data[3];
                }

                pub inline fn toVec2(self: Self) GenericVector(2, T) {
                    return GenericVector(2, T).fromVec4(self);
                }

                pub inline fn toVec3(self: Self) GenericVector(3, T) {
                    return GenericVector(3, T).fromVec4(self);
                }

                pub inline fn fromVec2(vec2: GenericVector(2, T), vz: T, vw: T) Self {
                    return Self.new(vec2.x(), vec2.y(), vz, vw);
                }

                pub inline fn fromVec3(vec3: GenericVector(3, T), vw: T) Self {
                    return Self.new(vec3.x(), vec3.y(), vec3.z(), vw);
                }
            },
            else => unreachable,
        };

        pub const new = DimensionImpl.new;

        pub inline fn x(self: Self) T {
            return self.data[0];
        }

        pub inline fn y(self: Self) T {
            return self.data[1];
        }

        pub const z = DimensionImpl.z;
        pub const w = DimensionImpl.w;

        pub inline fn xMut(self: *Self) *T {
            return &self.data[0];
        }

        pub inline fn yMut(self: *Self) *T {
            return &self.data[1];
        }

        pub const zMut = DimensionImpl.zMut;
        pub const wMut = DimensionImpl.wMut;

        /// Set all components to the same given value.
        pub fn set(val: T) Self {
            const result: Data = @splat(val);
            return .{ .data = result };
        }

        /// Shorthand for (0..).
        pub fn zero() Self {
            return set(0);
        }

        /// Shorthand for (1..).
        pub fn one() Self {
            return set(1);
        }

        /// Shorthand for (0, 1).
        pub fn up() Self {
            return switch (dimensions) {
                2 => Self.new(0, 1),
                3 => Self.new(0, 1, 0),
                4 => Self.new(0, 1, 0, 0),
                else => unreachable,
            };
        }

        /// Shorthand for (0, -1).
        pub fn down() Self {
            return up().negate();
        }

        /// Shorthand for (1, 0).
        pub fn right() Self {
            return switch (dimensions) {
                2 => Self.new(1, 0),
                3 => Self.new(1, 0, 0),
                4 => Self.new(1, 0, 0, 0),
                else => unreachable,
            };
        }

        /// Shorthand for (-1, 0).
        pub fn left() Self {
            return right().negate();
        }

        pub const forward = DimensionImpl.forward;
        pub const back = DimensionImpl.back;

        /// Negate the given vector.
        pub fn negate(self: Self) Self {
            return self.scale(-1);
        }

        /// Cast a type to another type.
        /// It's like builtins: @intCast, @floatCast, @floatFromInt, @intFromFloat.
        pub fn cast(self: Self, comptime dest_type: type) GenericVector(dimensions, dest_type) {
            const dest_info = @typeInfo(dest_type);

            if (dest_info != .float and dest_info != .int) {
                panic("Error, dest type should be integer or float.\n", .{});
            }

            var result: [dimensions]dest_type = undefined;

            for (result, 0..) |_, i| {
                result[i] = math.lossyCast(dest_type, self.data[i]);
            }
            return .{ .data = result };
        }

        /// Construct new vector from slice.
        pub fn fromSlice(slice: []const T) Self {
            const result = slice[0..dimensions].*;
            return .{ .data = result };
        }

        pub const fromVec2 = DimensionImpl.fromVec2;
        pub const fromVec3 = DimensionImpl.fromVec3;
        pub const fromVec4 = DimensionImpl.fromVec4;

        pub const toVec2 = DimensionImpl.toVec2;
        pub const toVec3 = DimensionImpl.toVec3;
        pub const toVec4 = DimensionImpl.toVec4;

        /// Transform vector to array.
        pub fn toArray(self: Self) [dimensions]T {
            return self.data;
        }

        /// Return the angle (in degrees) between two vectors.
        pub fn getAngle(first_vector: Self, second_vector: Self) T {
            const dot_product = dot(norm(first_vector), norm(second_vector));
            return root.toDegrees(math.acos(dot_product));
        }

        /// Return the length (magnitude) of given vector.
        /// √[x^2 + y^2 + z^2 ...]
        pub fn length(self: Self) T {
            return @sqrt(self.dot(self));
        }

        /// Return the length (magnitude) squared of given vector.
        /// x^2 + y^2 + z^2 ...
        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        /// Return the distance between two points.
        /// √[(x1 - x2)^2 + (y1 - y2)^2 + (z1 - z2)^2 ...]
        pub fn distance(first_vector: Self, second_vector: Self) T {
            return length(first_vector.sub(second_vector));
        }

        /// Return the distance squared between two points.
        /// (x1 - x2)^2 + (y1 - y2)^2 + (z1 - z2)^2 ...
        pub fn distanceSq(first_vector: Self, second_vector: Self) T {
            return lengthSq(first_vector.sub(second_vector));
        }

        /// Construct new normalized vector from a given one.
        pub fn norm(self: Self) Self {
            const l = self.length();
            if (l == 0) {
                return self;
            }
            const result = self.data / @as(Data, @splat(l));
            return .{ .data = result };
        }

        /// Return true if two vectors are equals.
        pub fn eql(first_vector: Self, second_vector: Self) bool {
            return @reduce(.And, first_vector.data == second_vector.data);
        }

        /// Substraction between two given vector.
        pub fn sub(first_vector: Self, second_vector: Self) Self {
            const result = first_vector.data - second_vector.data;
            return .{ .data = result };
        }

        /// Addition betwen two given vector.
        pub fn add(first_vector: Self, second_vector: Self) Self {
            const result = first_vector.data + second_vector.data;
            return .{ .data = result };
        }

        /// Component wise multiplication betwen two given vector.
        pub fn mul(first_vector: Self, second_vector: Self) Self {
            const result = first_vector.data * second_vector.data;
            return .{ .data = result };
        }

        /// Component wise division betwen two given vector.
        pub fn div(first_vector: Self, second_vector: Self) Self {
            const result = first_vector.data / second_vector.data;
            return .{ .data = result };
        }

        /// Construct vector from the max components in two vectors
        pub fn max(first_vector: Self, second_vector: Self) Self {
            const result = @max(first_vector.data, second_vector.data);
            return .{ .data = result };
        }

        /// Construct vector from the min components in two vectors
        pub fn min(first_vector: Self, second_vector: Self) Self {
            const result = @min(first_vector.data, second_vector.data);
            return .{ .data = result };
        }

        /// Construct new vector after multiplying each components by a given scalar
        pub fn scale(self: Self, scalar: T) Self {
            const result = self.data * @as(Data, @splat(scalar));
            return .{ .data = result };
        }

        /// Return the dot product between two given vector.
        /// (x1 * x2) + (y1 * y2) + (z1 * z2) ...
        pub fn dot(first_vector: Self, second_vector: Self) T {
            return @reduce(.Add, first_vector.data * second_vector.data);
        }

        /// Linear interpolation between two vectors
        pub fn lerp(first_vector: Self, second_vector: Self, t: T) Self {
            const from = first_vector.data;
            const to = second_vector.data;

            const result = from + (to - from) * @as(Data, @splat(t));
            return .{ .data = result };
        }

        pub const rotate = DimensionImpl.rotate;
        pub const cross = DimensionImpl.cross;

        /// Comptime vector component swizzle. Accepts component names, 0, or 1.
        pub fn swizzle(self: Self, comptime comps: []const u8) SwizzleType(comps.len) {
            // Someone doing a single component swizzle with 0 or 1 is weird but... it's supported...
            if (comps.len == 1) {
                return switch (comps[0]) {
                    '0' => 0,
                    '1' => 1,
                    else => self.data[@intFromEnum(@field(Component, &.{comps[0]}))],
                };
            }

            var result = GenericVector(comps.len, T).zero();
            inline for (comps, 0..) |comp, i| {
                switch (comp) {
                    '0' => result.data[i] = 0,
                    '1' => result.data[i] = 1,
                    else => result.data[i] = self.data[@intFromEnum(@field(Component, &.{comp}))],
                }
            }
            return result;
        }

        fn SwizzleType(comps_len: usize) type {
            return switch (comps_len) {
                1 => T,
                else => GenericVector(comps_len, T),
            };
        }

        /// Deprecated; use `swizzle` instead
        pub inline fn swizzle2(self: Self, comptime vx: Component, comptime vy: Component) GenericVector(2, T) {
            return self.swizzle(@tagName(vx) ++ @tagName(vy));
        }

        /// Deprecated; use `swizzle` instead
        pub inline fn swizzle3(self: Self, comptime vx: Component, comptime vy: Component, comptime vz: Component) GenericVector(3, T) {
            return self.swizzle(@tagName(vx) ++ @tagName(vy) ++ @tagName(vz));
        }

        /// Deprecated; use `swizzle` instead
        pub inline fn swizzle4(self: Self, comptime vx: Component, comptime vy: Component, comptime vz: Component, comptime vw: Component) GenericVector(4, T) {
            return self.swizzle(@tagName(vx) ++ @tagName(vy) ++ @tagName(vz) ++ @tagName(vw));
        }
    };
}
