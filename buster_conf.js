var config = module.exports;

config["Stats tests"] = {
    env: "node",        // or "browser"
    rootPath: "../",
    sources: [
        "barstat.js", // Paths are relative to config file
        //"lib/**/*.js"   // Glob patterns supported
    ],
    tests: [
        "test/tests.js"
    ]
}