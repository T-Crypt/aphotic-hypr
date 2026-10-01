function safeComponent(plugin, component) {
    if (typeof plugin !== 'string' || !/^[a-z][a-z0-9-]*$/.test(plugin)
        || typeof component !== 'string' || !component || /[%\\:#?\x00-\x1f]/.test(component)) return false;
    return !component.split('/').some(function(part) { return !part || part === '.' || part === '..'; });
}
