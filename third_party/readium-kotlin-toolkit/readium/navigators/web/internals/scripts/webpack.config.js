const path = require("path")
const CopyPlugin = require("copy-webpack-plugin")

module.exports = {
  mode: "production",
  devtool: "source-map",
  entry: {
    "fixed-single-script": "./src/index-fixed-single.ts",
    "fixed-double-script": "./src/index-fixed-double.ts",
    "fixed-injectable-script": "./src/index-fixed-injectable.ts",
    "reflowable-injectable-script": "./src/index-reflowable-injectable.ts",
  },
  resolve: {
    // Add '.ts' and '.tsx' as resolvable extensions.
    extensions: ["", ".webpack.js", ".web.js", ".ts", ".tsx", ".js"],
  },
  module: {
    rules: [
      // All files with a '.ts' or '.tsx' extension will be handled by 'ts-loader'.
      {
        test: /\.tsx?$/,
        loader: "ts-loader",
      },
      {
        test: /\.m?js$/,
        exclude: /node_modules/,
        use: {
          loader: "babel-loader",
          options: {
            presets: ["@babel/preset-env"],
          },
        },
      },
    ],
  },
  plugins: [
    new CopyPlugin({
      patterns: [
        { from: "public" },
        {
          from: "node_modules/@readium/css/css/dist",
          to: "readium-css",
          // BiblioLife does not ship the optional legacy Android FXL font patch.
          // Its Nimbus WOFF redistribution terms are not established, and the app
          // does not load this patch. Keep it excluded if Readium CSS is regenerated.
          globOptions: {
            ignore: ["**/android-fonts-patch/**"],
          },
          transform(content, absoluteFrom) {
            const sourcePath = absoluteFrom.replace(/\\\\/g, "/");
            if (sourcePath.endsWith("/ReadMe.md")) {
              const source = content.toString("utf8");
              return Buffer.from(source.replace(
                /## Android Fonts Patch[\\s\\S]*$/,
                "## Android Fixed-Layout system-font patch\\n\\nThe legacy Android Fonts Patch is excluded from this BiblioLife distribution because its Nimbus WOFF redistribution grant is not established. See docs/release/android-fxl-font-patch.md.\\n",
              ));
            }
            return content;
          },
        },
      ],
    }),
  ],
}
