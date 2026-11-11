<script lang="ts">
	import TextPage from '#lib/TextPage.svelte';
</script>

<svelte:head>
	<title>Support · Lamplens</title>
	<meta
		name="description"
		content="Questions or problems with Lamplens? Email us at support@lamplens.app, or use Send feedback in the app."
	/>
</svelte:head>

<TextPage
	title="Support"
	lead="Questions or problems? Email us, or use Send feedback in the app: it writes the email for you, with your device and app version already filled in."
	contactLabel="Email support"
	lastUpdated="Last updated 11 November 2026."
>
	{#snippet sections()}
		<h2>Back up or move your notes</h2>
		<p>In Settings, under Data, choose Export as Markdown or Export as JSON. Your iCloud or computer backups also include them.</p>

		<h2>Make the text bigger or smaller</h2>
		<p>In Settings, under Reading, use Text size. The app also follows your device’s text size.</p>

		<h2>Find your app version</h2>
		<p>In Settings, choose About and licences.</p>

		<h2>Translations</h2>
		<p>The King James Version, World English Bible, Berean Standard Bible, American Standard Version, Young’s Literal Translation, Darby and Webster are built in and work offline. All are in the public domain.</p>

		<h2>Privacy</h2>
		<p>Lamplens collects no data and never goes online. Read the <a href="/privacy/">privacy policy</a>.</p>
	{/snippet}
</TextPage>

<style>
	h2 {
		margin: 28px 0 0;
		font-weight: 500;
		font-size: var(--h2-text);
		line-height: 1.25;
		letter-spacing: -0.01em;
	}

	p {
		color: var(--ink);
	}

	p :global(a) {
		text-underline-offset: 4px;
	}
</style>
