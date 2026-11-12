/* eslint-env node */
/* eslint-disable @typescript-eslint/no-var-requires */

// builds the app's own boot entry against the upstream ollieos source in build/ollieos (cloned by build.sh).
// tools and dependencies come from upstream's node_modules so versions always match the os being built
const path = require("path");

const upstream_dir = path.resolve(__dirname, "../build/ollieos");
const upstream_modules = path.join(upstream_dir, "node_modules");

module.exports = (env) => ({
    mode: "production",
    devtool: false,
    entry: {
        main: path.resolve(__dirname, "src/index.ts"),
        fsedit: path.join(upstream_dir, "src/fsedit/index.ts"),
    },
    module: {
        rules: [
            {
                test: /\.tsx?$/,
                loader: "ts-loader",
                exclude: /node_modules/,
                options: {
                    // type checking is done separately with tsc (see build.sh), upstream files are checked by upstream
                    transpileOnly: true,
                    configFile: path.resolve(__dirname, "tsconfig.json"),
                },
            },
            {
                test: /\.css$/,
                oneOf: [
                    {
                        resourceQuery: /raw/,
                        type: "asset/source",
                    },
                    {use: ["style-loader", "css-loader"]},
                ],
            },
        ],
    },
    resolve: {
        extensions: [".ts", ".js"],
        alias: {
            ollieos: upstream_dir,
        },
        modules: [upstream_modules, "node_modules"],
    },
    resolveLoader: {
        modules: [upstream_modules],
    },
    output: {
        filename: "[name].bundle.js",
        chunkFilename: "[name].[contenthash].chunk.js",
        path: path.resolve(env.output_dir),
        clean: true,
    },
});
