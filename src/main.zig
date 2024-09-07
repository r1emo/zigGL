const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");

// Procedure table that will hold OpenGL functions loaded at runtime.
var procs: gl.ProcTable = undefined;

const Mesh = struct {
    vertices: [32]f32 = [1]f32{0} ** 32,
    vertexCount: u32 = 0,

    indices: [32]c_uint = [1]c_uint{0} ** 32,
    indexCount: u32 = 0,

    VBO: c_uint = undefined,
    VAO: c_uint = undefined,
    EBO: c_uint = undefined,

    fn createMesh(self: *Mesh) void {
        gl.GenVertexArrays(1, (&self.VAO)[0..1]); // create vertex array object
        gl.GenBuffers(1, (&self.VBO)[0..1]); // create vertex buffer object
        gl.GenBuffers(1, (&self.EBO)[0..1]); // create element buffer object

        // bind VAO first
        gl.BindVertexArray(self.VAO);

        // copy vertices array into buffer for OpenGL to use
        gl.BindBuffer(gl.ARRAY_BUFFER, self.VBO); // bind that VBO to the array buffer
        gl.BufferData(gl.ARRAY_BUFFER, self.vertexCount * @sizeOf(f32), &self.vertices, gl.STATIC_DRAW);

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.EBO);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, self.indexCount * @sizeOf(c_uint), &self.indices, gl.STATIC_DRAW);

        // set the vertex attributes pointers
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), 0);
        gl.EnableVertexArrayAttrib(self.VAO, 0);

        gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        gl.BindVertexArray(0);
    }

    fn bindMesh(self: *Mesh) void {
        gl.BindVertexArray(self.VAO);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.EBO);
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
    }

    fn deleteMesh(self: *Mesh) void {
        gl.DeleteVertexArrays(1, (&self.VAO)[0..1]);
        gl.DeleteBuffers(1, (&self.VBO)[0..1]);
        gl.DeleteBuffers(1, (&self.EBO)[0..1]);
    }
};

const Shader = struct {
    program: u32 = 0,
    vertexShader: u32 = 0,
    fragmentShader: u32 = 0,

    vertexSource: []const u8,
    fragmentSource: []const u8,

    // ! -- TODO: ADD ERROR HANDLING WITH SPECIFIC ERRORS FOR WHEN IT FAILS INSTEAD OF BEING LAZY
    fn createShader(self: *Shader) c_int {
        // get vertex shader and process it
        self.vertexShader = gl.CreateShader(gl.VERTEX_SHADER);
        gl.ShaderSource(self.vertexShader, 1, (&self.vertexSource.ptr)[0..1], null);
        gl.CompileShader(self.vertexShader);

        // variables used for tracking error logs
        var success: c_int = undefined;

        // check if vertex shader compiled successfully
        gl.GetShaderiv(self.vertexShader, gl.COMPILE_STATUS, &success);

        if (success == gl.FALSE)
            return success;

        // get fragment shader and process it
        self.fragmentShader = gl.CreateShader(gl.FRAGMENT_SHADER);
        gl.ShaderSource(self.fragmentShader, 1, (&self.fragmentSource.ptr)[0..1], null);
        gl.CompileShader(self.fragmentShader);

        // check if vertex shader compiled successfully
        gl.GetShaderiv(self.fragmentShader, gl.COMPILE_STATUS, &success);

        if (success == gl.FALSE)
            return success;

        self.program = gl.CreateProgram();

        gl.AttachShader(self.program, self.vertexShader);
        gl.AttachShader(self.program, self.fragmentShader);
        gl.LinkProgram(self.program);

        gl.GetProgramiv(self.program, gl.LINK_STATUS, &success);

        return success;
    }

    fn deleteShader(self: *Shader) void {
        gl.DeleteShader(self.vertexShader);
        gl.DeleteShader(self.fragmentShader);
        gl.DeleteProgram(self.program);
    }
};

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn processInput(window: glfw.Window) void {
    if (window.getKey(glfw.Key.escape) == glfw.Action.press)
        window.setShouldClose(true);
}

pub fn main() !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    defer glfw.terminate();

    // Create our window
    const window = glfw.Window.create(640, 480, "Learning OpenGL", null, null, .{}) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.CreateWindowFailed;
    };
    defer window.destroy(); // delete window when program ends

    glfw.makeContextCurrent(window);

    if (!procs.init(glfw.getProcAddress)) return error.GLInitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var infoLog: [512:0]u8 = undefined;

    var shader = Shader{
        .vertexSource = @embedFile("./shaders/triangleVertexShader.vert"),
        .fragmentSource = @embedFile("./shaders/triangleFragmentShader.frag"),
    };
    defer shader.deleteShader();

    if (shader.createShader() == gl.FALSE) {
        gl.GetShaderInfoLog(shader.vertexShader, 512, null, &infoLog);
        std.log.err("Failed to compile vertext shader: {s}", .{infoLog});
        gl.GetShaderInfoLog(shader.program, 512, null, &infoLog);
        std.log.err("Failed to create shader program: {s}", .{infoLog});
        gl.GetShaderInfoLog(shader.fragmentShader, 512, null, &infoLog);
        std.log.err("Failed to compile fragment shader: {s}", .{infoLog});
        return error.LinkProgramFailed;
    }

    // the points of our rectangle
    const vertices = [_]f32{
        // x, y, z
        0.5,  0.5,  0,
        0.5,  -0.5, 0,
        -0.5, -0.5, 0,
        -0.5, 0.5,  0,
    };

    // the order we want to draw said points
    const indices = [_]c_uint{
        0, 1, 3, // first triangle
        1, 2, 3, // second triangle
    };
    // we set it up this way so we only need 4 vertices not 6 since two are the same for both triangles making the rec

    var mesh = Mesh{};

    std.mem.copyBackwards(f32, &mesh.vertices, &vertices);
    mesh.vertexCount = vertices.len;

    std.mem.copyBackwards(c_uint, &mesh.indices, &indices);
    mesh.indexCount = indices.len;

    mesh.createMesh();
    defer mesh.deleteMesh();

    gl.PolygonMode(gl.FRONT_AND_BACK, gl.TRIANGLES);

    // process frames until the user says to close the window.
    while (!window.shouldClose()) {
        processInput(window);

        gl.ClearColor(0, 1, 0, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        // draw triangle
        gl.UseProgram(shader.program);
        mesh.bindMesh();

        window.swapBuffers();
        glfw.pollEvents();
    }
}
