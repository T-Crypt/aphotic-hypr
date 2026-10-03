function strings(value) {
    return Array.isArray(value) ? value.filter(function(v,i,a) { return typeof v === 'string' && v.length > 0 && v.length < 256 && a.indexOf(v) === i; }).slice(0,128) : [];
}
function edge(value) {
    value = value && typeof value === 'object' ? value : {};
    return {enabled:value.enabled === true, pinned:strings(value.pinned), tabs:strings(value.tabs),
        handles:value.handles === true, magnify:value.magnify === true, allOutputs:value.allOutputs === true};
}
function config(configs, output) {
    var saved = configs && Object.prototype.hasOwnProperty.call(configs,output) ? configs[output] : {};
    saved = saved && typeof saved === 'object' ? saved : {};
    return {description:typeof saved.description === 'string' ? saved.description : '', left:edge(saved.left), right:edge(saved.right)};
}
function validEdge(value) { return value === 'left' || value === 'right'; }
function update(configs, output, side, patch, description) {
    if (!output || !validEdge(side) || !patch || typeof patch !== 'object') return null;
    var next = Object.assign({},configs || {}), saved = config(configs,output);
    saved[side] = edge(Object.assign({},saved[side],patch));
    if (typeof description === 'string') saved.description = description;
    Object.defineProperty(next,output,{value:saved,enumerable:true,writable:true,configurable:true});
    return next;
}
function key(output,side) { return output + '/' + side; }
function reconcile(open, configs, outputs) {
    return (open || []).filter(function(k) {
        var at = k.lastIndexOf('/'), output = k.slice(0,at), side = k.slice(at+1);
        return outputs.indexOf(output) >= 0 && validEdge(side) && config(configs,output)[side].enabled;
    });
}
function command(side) { return 'qs -c aphotic ipc call shelves toggle ' + side; }
function conflict(binds,side) {
    var symbol = side === 'left' ? 'bracketleft' : 'bracketright';
    return !Array.isArray(binds) || binds.some(function(b) {
        return b && !b.mouse && (b.key === symbol || b.key === (side === 'left' ? '[' : ']')) && (b.modmask & 255) === 64
            && !(b.dispatcher === 'exec' && b.arg === command(side));
    });
}
