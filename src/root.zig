const std = @import("std");
const testing = std.testing;

pub const Sign = enum { positive, negative };
pub const Coefficents = std.ArrayList;

export const terms = struct {
    sign: Sign,
    coefficents: Coefficents,
};

export const expression = struct {
    terms: std.ArrayList(terms),
};

export const equation = struct {
    left: expression,
    right: expression,
};
