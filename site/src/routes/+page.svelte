<script lang="ts">
	import AppStoreButton from '#lib/AppStoreButton.svelte';
	import DeviceFrame from '#lib/DeviceFrame.svelte';
	import FeatureCard from '#lib/FeatureCard.svelte';
	import PaperPanel from '#lib/PaperPanel.svelte';

	const cards = [
		{
			title: 'Behind every word',
			body:
				'Press and hold any word for its meaning, then go deeper: the Hebrew or Greek word in the verse, how to say it, and what it means.'
		},
		{
			title: 'Seven translations',
			body:
				'King James (KJV), World English (WEB), Berean Standard (BSB), American Standard (ASV), Young’s Literal (YLT), Darby and Webster. All in the public domain, one tap apart.'
		},
		{
			title: 'Lightning fast',
			body:
				'Opens straight to your page and searches the whole Bible as fast as you can type. Every word is stored on your phone, so there is never anything to load.'
		},
		{
			title: 'Works anywhere',
			body:
				'Deep in a forest, out at sea, on a long flight or at a campsite with no signal. Every translation, voice and dictionary is already on your phone.'
		}
	];

	const shots = [
		{
			src: '/screenshots/read.jpg',
			alt: 'John 3 in the King James Version, typeset on sepia paper',
			title: 'Read',
			body: 'Typeset like a printed Bible, in light, sepia or dark.'
		},
		{
			src: '/screenshots/listen.jpg',
			alt: 'Read Aloud playing John 3 in sepia, with the Listening bar and its timer',
			title: 'Listen',
			body: 'A natural voice reads to you, even as you drift off to sleep.'
		},
		{
			src: '/screenshots/dig-deeper.jpg',
			alt: 'The Hebrew words of Genesis 1:1 in sepia, each with its pronunciation and meaning',
			title: 'Dig deeper',
			body: 'Any word, down to the Hebrew or Greek behind it.'
		}
	];
</script>

<svelte:head>
	<title>Lamplens</title>
	<meta
		name="description"
		content="A natural voice that reads aloud, seven translations, and the Hebrew and Greek behind every word. Lightning fast and all on your phone, with no account and no signal needed."
	/>
</svelte:head>

<main id="top">
	<section class="hero">
		<div class="hero-copy">
			<h1>Let the Bible speak to you.</h1>
			<p class="lead">
				A natural voice that reads aloud, seven translations, and the Hebrew and Greek behind every
				word. Lightning fast and all on your phone, with no account and no signal needed.
			</p>
			<div class="buy">
				<AppStoreButton />
				<span class="free"><strong>Free forever</strong> · iPhone and iPad</span>
			</div>
			<p class="note">[Apple’s official App Store badge replaces this button]</p>
		</div>
		<div class="hero-shot">
			<DeviceFrame
				src="/screenshots/hero-read-aloud.jpg"
				alt="Lamplens in sepia, reading John 3 aloud, with a bar in the margin beside the highlighted verse being read"
				width="min(290px, 68vw)"
				radius={44}
				bezel={9}
				screenRadius={35}
				shadow="var(--shadow-hero)"
			/>
		</div>
	</section>

	<section aria-labelledby="see-title" class="see">
		<h2 id="see-title">Read. Listen. Dig deeper.</h2>
		<div class="row" tabindex="0" role="group" aria-label="App screenshots">
			{#each shots as shot (shot.title)}
				<figure>
					<DeviceFrame src={shot.src} alt={shot.alt} width="100%" />
					<figcaption>
						<strong>{shot.title}</strong>
						<span>{shot.body}</span>
					</figcaption>
				</figure>
			{/each}
		</div>
	</section>

	<section aria-labelledby="voices-title" class="pair">
		<div class="copy">
			<h2 id="voices-title">Four voices. Choose the one you like.</h2>
			<p class="lead tight">
				Freya and Spencer are British, Harper and Russell are American. Every voice is built in and
				reads right on your phone, so it works with no signal. Change it whenever you like.
			</p>
			<div class="points">
				<p><strong>Fall asleep to it</strong>Set the sleep timer and it reads on into the next chapter, then fades out gently when the time is up.</p>
				<p><strong>Keep your place</strong>A thin bar in the margin marks the verse being read.</p>
			</div>
		</div>
		<div class="side">
			<DeviceFrame
				src="/screenshots/voices.jpg"
				alt="The four voices in sepia: Freya, Spencer, Harper and Russell, each with how it sounds"
				width="260px"
				radius={40}
				screenRadius={32}
			/>
		</div>
	</section>

	<section aria-labelledby="notes-title" class="pair reversed">
		<div class="copy">
			<h2 id="notes-title">Mark what matters to you.</h2>
			<p class="lead tight">
				Tap a verse to highlight it in one of six colours, write a note on it, or save it as a
				bookmark.
			</p>
			<div class="points">
				<p><strong>All in one place</strong>Your bookmarks, highlights and notes are gathered in one list. Tap any of them to jump straight back to the verse.</p>
				<p><strong>Yours to keep</strong>Everything stays on your phone and is included in its normal backup. You can export it whenever you like.</p>
			</div>
		</div>
		<div class="side">
			<DeviceFrame
				src="/screenshots/notes.jpg"
				alt="A verse in sepia, tapped, offering six highlight colours, a note and a bookmark"
				width="260px"
				radius={40}
				screenRadius={32}
			/>
		</div>
	</section>

	<section aria-labelledby="why-title" class="why">
		<h2 id="why-title">Made for unhurried reading</h2>
		<div class="grid">
			<FeatureCard title={cards[0].title}>
				{#snippet icon()}
					<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3A2E22" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6" /><path d="M15 15 L20 20" /></svg>
				{/snippet}
				{cards[0].body}
			</FeatureCard>
			<FeatureCard title={cards[1].title}>
				{#snippet icon()}
					<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3A2E22" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 5 L10 5 A2 2 0 0 1 12 7 L12 20 A2 2 0 0 0 10 18 L4 18 Z" /><path d="M20 5 L14 5 A2 2 0 0 0 12 7 L12 20 A2 2 0 0 1 14 18 L20 18 Z" /></svg>
				{/snippet}
				{cards[1].body}
			</FeatureCard>
			<FeatureCard title={cards[2].title}>
				{#snippet icon()}
					<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3A2E22" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13 3 L5 13.5 L11.5 13.5 L10.5 21 L19 10 L12.5 10 Z" /></svg>
				{/snippet}
				{cards[2].body}
			</FeatureCard>
			<FeatureCard title={cards[3].title}>
				{#snippet icon()}
					<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3A2E22" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3 L6 11 L9 11 L4.5 17 L19.5 17 L15 11 L18 11 Z" /><path d="M12 17 L12 21" /></svg>
				{/snippet}
				{cards[3].body}
			</FeatureCard>
		</div>
	</section>

	<section aria-labelledby="private-title" class="private">
		<h2 id="private-title">Nothing leaves your phone.</h2>
		<p class="lead">
			Lamplens never connects to the internet, not even once. There’s nothing to sign in to, nothing
			to opt out of, and no one watching what you read.
		</p>
	</section>

	<section aria-labelledby="belief-title" class="belief">
		<PaperPanel>
			<div class="belief-inner">
				<div class="belief-quote">
					<h2 id="belief-title">What we believe</h2>
					<blockquote>
						<p>“The word of God is not bound.”</p>
						<footer>2 Timothy 2:9</footer>
					</blockquote>
				</div>
				<p class="belief-body">
					We believe Scripture belongs to everyone. It shouldn’t sit behind licences, paywalls,
					sign-ins or usage rules. So Lamplens carries only translations that are free for anyone to
					read, copy and share, and it needs no servers, no subscriptions and no one’s permission.
					Nothing stands between you and the Word, and nothing ever will.
				</p>
			</div>
		</PaperPanel>
	</section>

	<section id="download" aria-labelledby="get-title" class="closing">
		<h2 id="get-title">Free forever</h2>
		<p class="lead center">
			For iPhone and iPad. No ads, no purchases, no subscription. Ever.
		</p>
		<AppStoreButton />
		<p class="verse">“Freely ye have received, freely give.” Matthew 10:8</p>
	</section>
</main>

<style>
	.hero {
		max-width: var(--container);
		margin: 0 auto;
		padding: clamp(24px, 4vw, 48px) var(--gutter) clamp(40px, 6vw, 72px);
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 32px 40px;
	}

	.hero-copy {
		flex: 1 1 380px;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 24px;
	}

	h1 {
		font-weight: 500;
		font-size: var(--h1);
		line-height: 1.06;
		letter-spacing: -0.025em;
		text-wrap: balance;
	}

	.lead {
		font-size: var(--lead);
		line-height: 1.55;
		color: var(--ink-soft);
		max-width: 500px;
	}

	.buy {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 16px;
		margin-top: 8px;
	}

	.free {
		font-size: 20px;
		line-height: 1.3;
		color: var(--ink-soft);
	}

	.free strong {
		font-weight: 700;
		color: var(--ink);
	}

	.note {
		font-size: 15px;
		color: var(--ink-faint);
	}

	.hero-shot {
		flex: 1 1 300px;
		display: flex;
		justify-content: center;
	}

	.see {
		padding: var(--section) 0;
	}

	.see h2,
	.why h2 {
		font-weight: 500;
		font-size: var(--h2);
		line-height: 1.2;
		letter-spacing: -0.015em;
		text-wrap: balance;
	}

	.see h2 {
		max-width: 1128px;
		margin: 0 auto;
		padding: 0 var(--gutter);
		text-align: center;
	}

	.row {
		max-width: 1128px;
		margin: 0 auto;
		display: flex;
		gap: clamp(20px, 3vw, 40px);
		overflow-x: auto;
		scroll-snap-type: x mandatory;
		padding: 40px var(--gutter) 44px;
		scrollbar-width: none;
	}

	figure {
		flex: 0 0 clamp(200px, 26vw, 240px);
		margin: 0;
		scroll-snap-align: center;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 20px;
	}

	figure:first-child {
		margin-left: auto;
	}

	figure:last-child {
		margin-right: auto;
	}

	figcaption {
		text-align: center;
	}

	figcaption strong {
		display: block;
		font-weight: 700;
		font-size: 22px;
		letter-spacing: -0.01em;
		color: var(--ink);
	}

	figcaption span {
		color: var(--ink-soft);
		font-size: 17px;
	}

	.pair {
		max-width: var(--container);
		margin: 0 auto;
		padding: var(--section) var(--gutter);
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 48px 40px;
	}

	.pair.reversed {
		flex-direction: row-reverse;
	}

	.copy {
		flex: 1 1 380px;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 20px;
	}

	.copy h2 {
		font-weight: 500;
		font-size: var(--h2);
		line-height: 1.2;
		letter-spacing: -0.015em;
		text-wrap: balance;
	}

	.lead.tight {
		max-width: 520px;
	}

	.points {
		margin-top: 8px;
		max-width: 520px;
		display: flex;
		flex-direction: column;
		border-top: 1px solid var(--rule);
	}

	.points p {
		padding: 18px 0;
		border-bottom: 1px solid var(--rule);
		color: var(--ink-soft);
	}

	.points strong {
		display: block;
		font-weight: 700;
		font-size: 20px;
		letter-spacing: -0.01em;
		color: var(--ink);
	}

	.side {
		flex: 1 1 260px;
		display: flex;
		justify-content: center;
	}

	.why {
		max-width: var(--container);
		margin: 0 auto;
		padding: var(--section) var(--gutter);
	}

	.why h2 {
		margin-bottom: 40px;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(340px, 100%), 1fr));
		gap: 20px;
	}

	.private {
		max-width: var(--container);
		margin: 0 auto;
		padding: var(--section) var(--gutter);
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		gap: 20px 56px;
	}

	.private h2 {
		flex: 1 1 320px;
		min-width: 0;
		font-weight: 500;
		font-size: var(--h2);
		line-height: 1.2;
		letter-spacing: -0.015em;
		text-wrap: balance;
	}

	.private .lead {
		flex: 1 1 320px;
		min-width: 0;
		max-width: none;
	}

	.belief {
		max-width: var(--container);
		margin: 0 auto;
		padding: clamp(24px, 3vw, 40px) var(--gutter);
	}

	.belief-inner {
		padding: clamp(32px, 6vw, 72px);
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		gap: 28px 56px;
	}

	.belief-quote {
		flex: 1 1 280px;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 20px;
	}

	.belief-quote h2 {
		font-weight: 500;
		font-size: var(--h2);
		line-height: 1.2;
		letter-spacing: -0.015em;
	}

	blockquote {
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	blockquote p {
		font-style: italic;
		font-size: var(--quote);
		line-height: 1.3;
		text-wrap: balance;
	}

	blockquote footer {
		font-size: 16px;
		color: var(--paper-ink-soft);
	}

	.belief-body {
		flex: 1 1 300px;
		min-width: 0;
		font-size: var(--body);
		line-height: 1.65;
		color: var(--paper-ink);
	}

	.closing {
		max-width: var(--container);
		margin: 0 auto;
		padding: clamp(56px, 8vw, 104px) var(--gutter);
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 20px;
	}

	.closing h2 {
		font-weight: 500;
		font-size: var(--h1);
		line-height: 1.06;
		letter-spacing: -0.025em;
	}

	.lead.center {
		max-width: 520px;
	}

	.verse {
		margin-top: 8px;
		font-style: italic;
		color: var(--ink-soft);
	}
</style>
