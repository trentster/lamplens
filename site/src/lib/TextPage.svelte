<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		title,
		lead,
		contactLabel,
		lastUpdated,
		sections
	}: {
		title: string;
		lead: string;
		contactLabel: string;
		lastUpdated: string;
		sections: Snippet;
	} = $props();
</script>

<main>
	<article>
		<h1>{title}</h1>
		<p class="lead">{lead}</p>
		<div class="sections">
			{@render sections()}
		</div>
		<div class="contact">
			<p class="label">{contactLabel}</p>
			<a href="mailto:support@lamplens.app">support@lamplens.app</a>
		</div>
		<p class="updated">{lastUpdated}</p>
	</article>
</main>

<style>
	main {
		max-width: var(--container);
		margin: 0 auto;
		padding: clamp(32px, 5vw, 64px) var(--gutter) clamp(56px, 8vw, 96px);
	}

	article {
		max-width: 680px;
		display: flex;
		flex-direction: column;
		gap: 20px;
	}

	h1 {
		font-weight: 500;
		font-size: clamp(40px, 5.6vw, 60px);
		line-height: 1.1;
		letter-spacing: -0.025em;
	}

	.lead {
		font-size: var(--lead);
		line-height: 1.55;
		color: var(--ink-soft);
	}

	.sections {
		display: flex;
		flex-direction: column;
		gap: 20px;
	}

	.contact {
		margin-top: 28px;
		background: var(--paper);
		color: var(--paper-ink);
		border-radius: 20px;
		padding: 28px 32px;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.label {
		font-size: 16px;
		color: var(--paper-ink-soft);
	}

	.contact a {
		font-size: 21px;
		color: var(--paper-ink);
		text-underline-offset: 5px;
		padding: 6px 0;
	}

	.updated {
		margin-top: 12px;
		font-size: 15px;
		color: var(--ink-faint);
	}
</style>
