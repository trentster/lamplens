<!-- A placeholder for Apple's official badge, exactly as the design draws it: same size, same words,
     and the note under the hero says so. -->
<a class="badge" href="#download" aria-label="Download on the App Store (official badge goes here)">
	<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
		<rect x="3" y="3" width="18" height="18" rx="5" />
		<path d="M9 15 L12 8 L15 15" />
		<path d="M10 13 L14 13" />
	</svg>
	<span class="words"><span class="small">Download on the</span><span class="big">App Store</span></span>
</a>

<style>
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		background: var(--button);
		color: #ffffff;
		text-decoration: none;
		border-radius: 12px;
		padding: 12px 22px;
		min-height: 48px;
		font-family: var(--sans);
	}

	.badge:hover {
		color: #ffffff;
	}

	.words {
		display: flex;
		flex-direction: column;
		line-height: 1.15;
		text-align: left;
	}

	.small {
		font-size: 12px;
	}

	.big {
		font-size: 19px;
		font-weight: 600;
	}
</style>
