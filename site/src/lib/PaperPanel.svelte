<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children, radius = 28 }: { children: Snippet; radius?: number } = $props();
</script>

<div class="paper" style:border-radius="{radius}px">
	{@render children()}
</div>

<style>
	.paper {
		background: var(--paper);
		color: var(--paper-ink);
	}
</style>
