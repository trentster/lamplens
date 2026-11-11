<script lang="ts">
	import type { Snippet } from 'svelte';

	let { title, children, icon }: { title: string; children: Snippet; icon: Snippet } = $props();
</script>

<div class="card">
	<span class="tile">{@render icon()}</span>
	<h3>{title}</h3>
	<p>{@render children()}</p>
</div>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: 12px;
		background: var(--surface);
		border-radius: 24px;
		padding: clamp(24px, 3.4vw, 36px);
	}

	.tile {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		align-self: flex-start;
		width: 52px;
		height: 52px;
		border-radius: 14px;
		background: var(--gold);
		margin-bottom: 8px;
	}

	h3 {
		font-size: var(--card-heading);
		font-weight: 700;
		line-height: 1.25;
		letter-spacing: -0.01em;
		color: var(--ink);
		white-space: nowrap;
	}

	p {
		font-size: var(--body);
		color: var(--ink-soft);
	}
</style>
