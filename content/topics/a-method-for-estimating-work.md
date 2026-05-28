---
share: true
aliases:
  - ⏱️📊 A Method For Estimating Work
title: ⏱️📊 A Method For Estimating Work
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-18T00:00:00Z
force_analyze_links: false
image_date: 2026-04-08T17:33:34Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, flat-style illustration featuring a sleek hourglass centered on a clean, soft-toned background. The hourglass is stylized with two distinct, glowing bands of color—a vibrant teal representing the tight P5 lower bound and a warm amber representing the broader P95 upper bound. Floating around the hourglass are small, abstract geometric shapes (circles and squares) representing data points, some perfectly aligned within the colored bands and a few scattered slightly outside to symbolize calibration and outliers. The aesthetic is clean, professional, and modern, using a limited color palette of navy, slate, teal, and amber to evoke a sense of precision, analytical thinking, and effective time management. There is subtle lighting that casts a soft shadow, giving the composition depth while maintaining a focus on the concept of probabilistic estimation.
link_analysis_version: "2"
URL: https://bagrounds.org/topics/a-method-for-estimating-work
updated: 2026-05-28T05:41:58
---
[Home](../index.md) > [Topics](./index.md)  
# ⏱️📊 A Method For Estimating Work  
![topics-a-method-for-estimating-work](../topics-a-method-for-estimating-work.jpg)  
## Method  
For each task, record a P5 and a P95 estimate for how much time you'd expect to pass before the work is done if it were yours to complete.  
  
## Definitions  
1. Task  
2. P5 estimate - a soft lower bound. In the long run, a calibrated estimator completes 5% of estimated tasks before their P5 estimate for that task.  
3. P95 estimate - a soft upper bound. In the long run, a calibrated estimator completes 95% of estimated tasks before their P95 estimate for that task.  
4. Time  
5. Done - task specific, well defined, testable criteria indicating that a task is complete  
  
## Execution  
1.   
  
## Calibration  
When a calibrated estimator has completed 20 estimated tasks  
1. exactly 1 task was completed before their P5 estimate for that task  
2. exactly 1 task was completed after their P95 estimate for that task  
3. the duration of the remaining 18 tasks fell between their corresponding P5 and P95 estimates  
Of course, this is also true in percentage terms, regardless of the population of tasks considered.  
Depending on the nature of the work, context, and the estimator's experience this may be easy or hard to achieve.  
An estimator should observe their task durations relative to their estimates and regularly review their overall performance.  
Observing how our completed task durations differ from our estimates informs how we should adjust our judgements.  
  
## Miscalibrations  
1. Optimistic upper bounds. More than 5% of tasks are completed after our P95 estimates.  
2. Optimistic lower bounds. Fewer than 5% of tasks are completed before our P5 estimates.  
3. Pessimistic lower bounds. More than 5% of tasks are completed before our P5 estimates.  
4. Pessimistic upper bounds. Fewer than 5% of tasks are completed after our P95 estimates.  
5. Unjustified precision. Too many durations fall outside of our estimates on either side.  
  1. Extreme case: P5 = P95  
  2. Our estimates are never correct.  
6. Unjustified uncertainty. Too many durations fall inside our estimates.  
    1. Extreme case: P5 = 0, P95 = infinity  
    2. Our estimates are always correct.  
  
## Improving Estimates  
1. Break down complicated tasks  
  2. Imagine a world where this task is done.  
  3. Imagine the world when this task is started.  
  4. Imagine doing the work required to complete this task.  
  5. Write down the steps.  
  6. Write down P5 and P95 estimates for each step.  
2. Review your task performance relative to your estimates regularly.  
3. When completing a task, reflect on surprises.  
    1. What took more or less time than you expected?  
  
## Teamwork  
1. A second estimator opens the door to learning and collaboration. When estimates differ significantly  
    1. Maybe there's something one estimator isn't considering  
    2. Maybe there's something one can learn from the other  
2. Breaking down work  
    1. is often much faster than completing the task  
    2. invites collaborative planning. Improving a plan is often faster, easier, cheaper, and feasible compared to improving a completed task.  
    3. produces a reference plan that someone else may use for a similar task in the future.  
    4. highlights processes that may be learned from or improved upon  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mmof7a2v6u2c" data-bluesky-cid="bafyreifwzxf6pemn5uesyex75h2zosfgb4rcgr4chhyvrz5kjxav2x2lbu"><p>⏱️📊 A Method For Estimating Work  
  
#AI Q: 🗓️ How often do you underestimate how long a project will take?  
  
Selection:*  
https://bagrounds.org/topics/a-method-for-estimating-work</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mmof7a2v6u2c?ref_src=embed">2026-05-25T11:36:33.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116650601721055158/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116650601721055158" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>