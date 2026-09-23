function surfacesFor(registrations, installed, surface, sheltered) {
    return (registrations || []).filter(entry => entry.surface === surface
        && !(sheltered && installed?.[entry.plugin]?.shelter === "unload"));
}
