// BonitoMail in the browser: the thread list's selection and the frames that
// show HTML mail.

// A click on a row selects its thread. The selected thread's row is marked,
// whoever selected it: a click here, or Julia.
export class ThreadList {
    constructor(root, selected) {
        this.root = root;
        root.addEventListener('click', event => {
            const row = event.target.closest('[data-thread]');
            if (row) selected.notify(row.dataset.thread);
        });
        selected.on(id => { this.mark(id); });
    }

    mark(id) {
        for (const row of this.root.querySelectorAll('.bm-thread.bm-active')) {
            row.classList.remove('bm-active');
        }
        const row = this.root.querySelector(`[data-thread="${CSS.escape(id)}"]`);
        if (row) row.classList.add('bm-active');
    }
}

// An HTML mail in its sandboxed frame, as tall as its content. The frame is
// same-origin without scripts, so its document can be measured from here.
export function fitFrame(frame) {
    const fit = () => {
        const doc = frame.contentDocument;
        if (!doc || !doc.body) return;
        // `body.scrollHeight` also when the mail sets `height: 100%` on html.
        const height = Math.max(doc.documentElement.offsetHeight, doc.body.scrollHeight);
        frame.style.height = height + 'px';
    };
    const watch = () => {
        fit();
        if (frame.contentDocument?.body) new ResizeObserver(fit).observe(frame.contentDocument.body);
    };
    frame.addEventListener('load', watch);
    if (frame.contentDocument?.readyState === 'complete') watch();
    // A frame inside a closed <details> has no size until it opens.
    new ResizeObserver(fit).observe(frame);
}
