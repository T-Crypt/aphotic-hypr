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

// Strata serves one model, so its report is one entry, and only while that
// model is resident. `arenaMiB` is the engine's own expert arena as the
// engine reported it; a host total is never passed here, so a claim can
// never be built from one.
function strataModels(health, arenaMiB) {
    if (!health?.model || health.loaded !== true)
        return [];
    return [{
        name: String(health.model),
        embedding: false,
        state: "loaded",
        ramMiB: Number(arenaMiB || 0)
    }];
}
