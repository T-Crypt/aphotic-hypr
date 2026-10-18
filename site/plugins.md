---
layout: default
title: Plugins
description: The current public Aphotic plugin roster.
---
<section class="page hero"><p class="eyebrow">Plugins</p><h1>Optional by design.</h1><p class="lede">The base shell stays focused. Plugins add interfaces, hooks, and profiles without becoming permanent core behavior.</p></section><section class="page prose"><h2>Explore the registry</h2><p>The public registry includes UI surfaces, harness hooks, profiles, and theme hooks. The complete current roster and its capability contracts live in the <a href="{{ '/docs/plugin-system/' | relative_url }}">Plugin System documentation</a>.</p><pre><code>aphotic plugin list --remote
aphotic plugin list --remote --refresh
aphotic plugin install &lt;name&gt;</code></pre><p>The catalogue caches to disk after the first fetch, so listing stays fast as the registry grows. Pass <code>--refresh</code> to fetch it again.</p></section>

<section class="page prose"><h2>Components and descriptors</h2><p>The components plugins build on stay stable. <code>Interact</code> is the current component for hover and press. <code>StateLayer</code> stays for compatibility and wraps <code>Interact</code>, so plugins written against it keep loading.</p><p>A plugin declares an agent harness with a <code>[harness.&lt;id&gt;]</code> table in its manifest, and a drop-in at <code>~/.config/aphotic/harnesses/&lt;id&gt;.toml</code> overrides a manifest descriptor or adds a harness of your own. <code>aphotic agent harnesses</code> merges both sources. The <code>engine</code> capability works the same way for inference engines, with an <code>[engine]</code> block and drop-ins at <code>~/.config/aphotic/engines/&lt;id&gt;.toml</code>; descriptors are parsed and validated, and the surfaces that consume them come later.</p></section>

<section class="page prose"><h2>Shelf tab contracts</h2><p>The Sonar and Shelves feature under review adds edge tabs with output placement and lifecycle gates. See the <a href="{{ '/docs/plugin-system/#shelf-tabs-and-sonar' | relative_url }}">plugin contract</a> and <a href="{{ '/docs/sonar-and-shelves/' | relative_url }}">controls</a>.</p></section>
