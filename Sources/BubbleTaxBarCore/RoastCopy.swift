import Foundation

public enum RoastScenario: String {
    case free, missing, stale, warming, localWaste, localMixed, active
    case remaining, expiring, wasted, unverified, workUnknown, workWaste, workActive
}

enum RoastCopy {
    // Pairs stay together: the follow-up must support the same evidence as the opener.
    static func lines(_ scene: RoastScenario) -> [(String, String)] {
        switch scene {
        case .free: return [
            ("Free plan? You beat the billing allegations.", "No subscription money to roast. Carry on."),
            ("Finally. Someone who read the price tag.", "Free tier. Financially unbothered."),
            ("AI bubble contribution: $0.", "The free-plan lifestyle looks good on you."),
            ("You brought a free plan to a subscription fight.", "Respect. Keep your wallet out of this."),
            ("Token testing. Zero billing.", "No paid plan reported. You're off the hook."),
            ("Free-tier behavior. Excellent wallet hygiene.", "Nothing to cancel here.")]
        case .missing: return [
            ("Please tell me you're not paying for {plan}.", "Missing receipts. The roast is pending."),
            ("You wouldn't be paying for {service}, right?", "Connect your usage. I need receipts before allegations."),
            ("Are you flexing {plan}, or actually using it?", "If you're subscribed, let's see the quota first."),
            ("The subscription allegations are unverified.", "No reliable usage yet. I'm reserving judgment."),
            ("Your tokens have entered witness protection.", "Can't read the quota. Can't call it wasted."),
            ("AI bubble sponsor? Allegedly.", "If you're paying, connect the receipts first.")]
        case .stale: return [
            ("Old receipts. Fresh suspicion.", "Hit refresh before I start making allegations."),
            ("This quota has been left on read.", "The data is stale. Your current balance could be different."),
            ("The roast is buffering.", "Refresh the usage. I refuse to bully a cached number."),
            ("Even my side-eye needs an update.", "These receipts are out of date."),
            ("Yesterday's quota is not today's tea.", "Fresh usage first. Financial bullying second.")]
        case .warming: return [
            ("You wouldn't be paying for {service}, right?", "Too early to judge. Let the receipts pile up."),
            ("New subscription energy. Let's see how long it lasts.", "Not enough history for a cancellation verdict."),
            ("The honeymoon phase has entered the chat.", "A few local logs aren't the whole relationship."),
            ("{plan}? Bold, if true.", "Let's get some history before the roast."),
            ("Your subscription is on probation.", "Gathering receipts. No verdict yet.")]
        case .localWaste: return [
            ("Bro, you're paying for {service}?", "If these local logs tell the whole story, review that renewal."),
            ("You pay for {service} just to ghost it?", "Quiet local logs. If that's all your usage, this is expensive silence."),
            ("On {plan}? That's a lot of subscription lore.", "If the local logs cover your usage, maybe downgrade the plot."),
            ("AI bubble sponsor? Your local logs are giving yes.", "If you aren't using it elsewhere, review the subscription."),
            ("Please tell me you're not flexing {plan} in public.", "If these logs are the whole story, the receipts are embarrassing."),
            ("Token maxxing? The local logs say token napping.", "Usage elsewhere could change the story. Check before renewing."),
            ("Your {service} subscription has separation anxiety.", "You barely visit it locally. Is it earning another renewal?"),
            ("Paying full-time. Logging in part-time.", "If the local logs cover everything, cancel it and send me the money.")]
        case .localMixed: return [
            ("{service}: it's complicated.", "Some local activity. Is that enough for another renewal?"),
            ("Premium commitment. Part-time situationship.", "These local receipts deserve a subscription review."),
            ("You and {service} need to define the relationship.", "Use it elsewhere? Include that before deciding."),
            ("Renewal day is not a loyalty test.", "Keep it for the value, not the streak."),
            ("A subscription isn't a personality trait.", "Do these receipts justify another month?")]
        case .active: return [
            ("Okay. You beat the token-wasting allegations.", "Real use showed up. Keep it if the value justifies the price."),
            ("The usage receipts actually showed up.", "A cheaper tier could still be enough. Usage alone isn't a value verdict."),
            ("Fine. This one isn't just subscription cosplay.", "You're using it. Check whether you need this much plan."),
            ("The roast has been downgraded.", "This quota gets used. The subscription still has to earn its price."),
            ("You brought receipts. I brought the wrong attitude.", "Real activity. Keep the plan for its value, not the flex."),
            ("Financial bullying postponed.", "{service} gets used. Is this the cheapest tier that does the job?")]
        case .remaining: return [
            ("{left} left. Auto-renew would like a word.", "This window is still open. Watch whether this much headroom keeps going unused."),
            ("You bought the whole menu. Needed one snack?", "{left} left so far. More history will tell us whether a smaller plan fits."),
            ("{plan}? Please tell me it's more than a flex.", "{left} left in this window. Review the tier if that becomes a pattern."),
            ("Your wallet doesn't get points for loyalty.", "{left} left. Keep the subscription for what you need, not what you could use."),
            ("A premium plan isn't a personality trait.", "{left} left so far. Does a cheaper tier cover your actual needs?"),
            ("Don't let auto-renew be your most active feature.", "{left} left in an open window. Check the reset history before deciding."),
            ("Subscription commitment. Usage still pending.", "{left} left for now. One unfinished window isn't a cancellation verdict."),
            ("Big-plan energy. Does the job need it?", "{left} left. Compare your normal usage with a cheaper tier.")]
        case .expiring: return [
            ("Reset is close. Renewal deserves a second look.", "{left} left near reset. If this keeps happening, review a cheaper tier."),
            ("Auto-renew is not a loyalty test.", "{left} left near reset. Keep the plan for the work you actually need."),
            ("The quota resets. The bill keeps its schedule.", "{left} left near reset. Repeated unused headroom can mean an oversized plan."),
            ("Your plan might be bigger than your workload.", "{left} left near reset. Check past windows before downgrading."),
            ("{plan}? That's a lot of room for a small routine.", "{left} left near reset. A recurring pattern would be a reason to review the tier."),
            ("The subscription has main-character billing.", "{left} left near reset. Does its role in your workflow justify the price?"),
            ("Please don't prompt just to justify the bill.", "{left} left near reset. A smaller plan may fit better if this repeats."),
            ("The buffet charges even when you're not hungry.", "{left} left near reset. Review the subscription if you keep leaving this much behind.")]
        case .wasted: return [
            ("You're doing your part to inflate the AI bubble.", "{unused} left near reset, on average. Generous of you."),
            ("Token maxxing? You're token trashing.", "These expired-window receipts averaged {unused} left."),
            ("Please tell me you're not flexing {plan} in public.", "{unused} left near reset. The receipts have jokes."),
            ("Your subscription is an AI-company donation.", "{unused} left near reset, on average. Review that renewal."),
            ("You bought compute and collected dust.", "Observed expired-window balance: {unused} left on average."),
            ("Token wasting. Premium edition.", "{unused} left near reset. Paying for headroom you keep leaving behind?"),
            ("The AI bubble called. It said thanks.", "{unused} left near reset, on average. You're very supportive."),
            ("This plan is getting paid to do nothing.", "{unused} left near reset. Maybe downgrade before the next encore."),
            ("Your best prompt is apparently auto-renew.", "{unused} left near reset, on average. Let's review that subscription."),
            ("Cancel the unused headroom. Send me the money.", "These observed windows averaged {unused} left near reset.")]
        case .unverified: return [
            ("If you're paying for {service}, we need to talk.", "{unused} left near reset. The paid-plan part is unverified."),
            ("AI bubble sponsor? Only if you're actually paying.", "Observed expired windows averaged {unused} left."),
            ("Token trashing. Billing status: a mystery.", "{unused} left near reset. Is this even a paid plan?"),
            ("You wouldn't be flexing {plan}, right?", "If you're subscribed, {unused} left near reset is a receipt to review."),
            ("These unused tokens have questions.", "{unused} left near reset. Check who pays before reviewing the plan.")]
        case .workUnknown: return [
            ("Your boss is gonna love this.", "Work plan. Missing seat receipts. Let's see what it earns."),
            ("Procurement has entered the chat.", "A work seat isn't proof of personal usage. Need better receipts."),
            ("Company plan. Main-character budget.", "Let's check whether this seat is getting used."),
            ("Your boss wants a word. Probably.", "Missing usage receipts. No seat verdict yet."),
            ("Corporate tokens. Unverified productivity.", "Let's gather the seat receipts before the roast.")]
        case .workWaste: return [
            ("Your boss is gonna love this. /s", "Unused headroom on a work plan. Review the seat, not your personal billing."),
            ("{workplan} plan. Intern-level token movement.", "If these limits represent your seat, review the allocation."),
            ("Don't tell your boss. Buy AI stocks instead. /s", "Work budget, not your personal savings. Review the seat with your workspace owner."),
            ("This seat is mostly just sitting there.", "Review the license with whoever manages the workspace."),
            ("Token maxxing? More like budget napping.", "Unused work-plan headroom. Is this seat earning its keep?"),
            ("Procurement bought a very expensive chair.", "If these receipts cover your seat, consider returning the license."),
            ("The expense report is doing more work than the tokens.", "Workspace quotas may be shared. Review the seat in that context."),
            ("Company plan. Token trashing on company time.", "Review this seat's value with your workspace owner.")]
        case .workActive: return [
            ("Your boss can unclench.", "This work plan is showing real use."),
            ("A seat that actually earns its keep. Rare.", "These work-plan receipts showed up."),
            ("Corporate token maxxing. Approved.", "Check shared limits, but this is real usage."),
            ("Procurement finally has something to brag about.", "The work-plan quota is getting used."),
            ("Your boss is gonna love this. For real this time.", "This seat has usage receipts.")]
        }
    }
}
