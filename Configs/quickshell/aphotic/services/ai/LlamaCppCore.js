function _args(cmdline) {
    const args = [];
    let current = "";
    let quote = "";
    let escaped = false;
    for (const char of String(cmdline || "")) {
        if (escaped) {
            current += char;
            escaped = false;
        } else if (char === "\\" && quote !== "'") {
            escaped = true;
        } else if (quote) {
            if (char === quote)
                quote = "";
            else
                current += char;
        } else if (char === "'" || char === '"') {
            quote = char;
        } else if (/\s/.test(char)) {
            if (current) {
                args.push(current);
                current = "";
            }
        } else {
            current += char;
        }
    }
    if (escaped)
        current += "\\";
    if (current)
        args.push(current);
    return args;
}

function _flag(args, names) {
    let value = "";
    for (let i = 0; i < args.length; i++) {
        if (names.includes(args[i]) && i + 1 < args.length) {
            value = args[i + 1];
            i++;
            continue;
        }
        for (const name of names) {
            if (args[i].startsWith(`${name}=`))
                value = args[i].slice(name.length + 1);
        }
    }
    return value;
}

function parseCommand(cmdline) {
    const args = _args(cmdline);
    let host = _flag(args, ["--host"]) || "127.0.0.1";
    if (host === "0.0.0.0")
        host = "127.0.0.1";
    const parsedPort = parseInt(_flag(args, ["--port"]), 10);
    const port = parsedPort > 0 && parsedPort <= 65535 ? parsedPort : 8080;
    const modelPath = _flag(args, ["-m", "--model"]);
    const modelFile = modelPath.split(/[\\/]/).pop() || "";
    return {
        host: host,
        port: port,
        embedding: args.some(arg => ["--embedding", "--embeddings", "--reranking"].includes(arg)),
        alias: _flag(args, ["--alias"]),
        model: modelFile.replace(/\.gguf$/i, "")
    };
}

function managedParent(parentComm) {
    const parent = String(parentComm || "").trim();
    return parent === "llama-swap" || parent.startsWith("ollama");
}

function parseProcessLine(line) {
    const match = String(line || "").match(/^(\d+)\s+(\S+)\s*(.*)$/);
    if (!match)
        return null;
    return {
        pid: parseInt(match[1], 10),
        parentComm: match[2],
        cmdline: match[3]
    };
}

function fallbackName(parsed) {
    return parsed?.alias || parsed?.model || `llama-server:${parsed?.port || 8080}`;
}

function isLoopbackHost(host) {
    return ["127.0.0.1", "localhost", "::1", "[::1]"].includes(String(host || "").toLowerCase());
}
