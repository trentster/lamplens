<!-- The app icon's lamp, drawn as the design hands it over: a flame over a bowl. -->
<svg width={size} height={size} viewBox="0 0 64 64" aria-hidden="true">
	<rect width="64" height="64" rx="14" fill="#2D3A97" />
	<path d="M32 12 C38 22 41 27 41 32 A9 9 0 0 1 23 32 C23 27 26 22 32 12 Z" fill="#E3A43B" />
	<path d="M32 22 C35 27 36 30 36 33 A4 4 0 0 1 28 33 C28 30 29 27 32 22 Z" fill="#F4CB72" />
	<path d="M14 40 L50 40 A18 12 0 0 1 14 40 Z" fill="#F3EDE0" />
</svg>

<script lang="ts">
	let { size = 36 }: { size?: number } = $props();
</script>
