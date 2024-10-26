/**
 * Execute the javascript code in node.js.
 * @typedef {Object} Args
 * @property {string} code - Javascript code to execute, such as `console.log("hello world")`
 * @param {Args} args
 */
exports.run = function run({ code }) {
  let log = "";
  const oldStdoutWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = (chunk, _encoding, callback) => {
    log += chunk;
    if (callback) callback();
  };

  eval(code);
  
  process.stdout.write = oldStdoutWrite;
  return log;
}
