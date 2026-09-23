function ollamaEmbedding(response) {
    const capabilities = Array.isArray(response?.capabilities) ? response.capabilities : [];
    return capabilities.includes("embedding") && !capabilities.includes("completion");
}

function ollamaRunningModels(response, capabilities) {
    return (response?.models || []).filter(model => model?.name).map(model => ({
        name: String(model.name),
        size: Number(model.size || 0),
        size_vram: Number(model.size_vram || 0),
        embedding: capabilities?.[model.name] === true,
        state: String(model.state ?? "")
    }));
}

function lmStudioModels(response) {
    return (response?.data || []).filter(model => model?.id && model.state === "loaded").map(model => ({
        name: String(model.id),
        embedding: model.type === "embeddings",
        state: "ready"
    }));
}
