(() => {
  const money = (amount) => `Bs ${Number(amount || 0).toFixed(2)}`;
  const node = (tag, text, className) => {
    const element = document.createElement(tag);
    if (text !== undefined && text !== null) element.textContent = String(text);
    if (className) element.className = className;
    return element;
  };
  const safeOrderError = (error) => {
    const message = String(error?.message || "");
    const known = [
      "Local no encontrado",
      "Escribe tu nombre",
      "Este local aún no configuró su WhatsApp. Inténtalo más tarde.",
      "El carrito no es válido",
      "El carrito está vacío",
      "El carrito contiene un producto inválido",
      "La cantidad de un producto no es válida",
      "El carrito contiene productos repetidos",
      "No hay productos disponibles",
      "Uno o más productos ya no están disponibles. Actualiza el catálogo e inténtalo otra vez.",
    ];
    return known.find((candidate) => message.startsWith(candidate)) ||
      "No se pudo registrar el pedido. Comprueba tu conexión e inténtalo otra vez.";
  };

  window.startFideliStorefront = async (root, slug, config) => {
    document.title = "Tienda · Fideli";
    let store = null;
    const cart = new Map();
    let selectedCategory = "Todos";
    let loading = false;
    let sending = false;
    const receiptKey = `fideli-store-receipt:${slug}`;
    const checkoutKey = `fideli-store-checkout:${slug}`;
    const sessionRead = (key) => { try { return JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (_) { return null; } };
    const sessionSave = (key, data) => { try { sessionStorage.setItem(key, JSON.stringify(data)); } catch (_) {} };
    const sessionRemove = (key) => { try { sessionStorage.removeItem(key); } catch (_) {} };
    let lastRequest = sessionRead(checkoutKey);
    const requestFor = (payload) => {
      const fingerprint = JSON.stringify(payload);
      if (!lastRequest || lastRequest.fingerprint !== fingerprint) {
        const bytes = crypto.getRandomValues(new Uint8Array(16));
        bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
        const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
        lastRequest = {fingerprint, id: `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`};
        sessionSave(checkoutKey, lastRequest);
      }
      return lastRequest.id;
    };

    const renderMessage = (title, detail, retry = false) => {
      root.replaceChildren();
      const card = node("section", null, "storefront-message");
      card.append(node("div", "F", "storefront-brand"), node("h1", title), node("p", detail));
      if (retry) {
        const button = node("button", "Volver a intentar", "storefront-action");
        button.type = "button";
        button.addEventListener("click", load);
        card.append(button);
      }
      root.append(card);
    };

    const load = async () => {
      if (loading) return;
      loading = true;
      renderMessage("Abriendo la tienda", "Cargando el catálogo del local…");
      try {
        if (!window.supabase?.createClient) throw new Error("No se pudo conectar con la tienda. Comprueba tu conexión e inténtalo otra vez.");
        const client = window.supabase.createClient(config.url, config.key, {
          auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        });
        const { data, error } = await client.rpc("get_storefront", { p_slug: slug });
        if (error) throw error;
        if (!data || !Array.isArray(data.products)) throw new Error("No encontramos esta tienda. Revisa el enlace e inténtalo otra vez.");
        store = data;
        const color = /^#[0-9a-f]{6}$/i.test(data.button_color || '') ? data.button_color : '#171225';
        root.style.setProperty('--store-accent', color);
        const rgb = color.slice(1).match(/../g).map((v) => parseInt(v, 16) / 255)
          .map((v) => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
        const luminance = .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
        root.style.setProperty('--store-on-accent', luminance > .179 ? '#171225' : '#ffffff');
        const receipt = sessionRead(receiptKey);
        if (receipt?.id && Array.isArray(receipt.items)) renderSuccess(receipt);
        else renderCatalog();
      } catch (error) {
        const detail = String(error?.message || "").startsWith("No encontramos esta tienda")
          ? "Este enlace no corresponde a una tienda disponible. Revisa el enlace e inténtalo de nuevo."
          : "Comprueba tu conexión y vuelve a intentarlo en unos minutos.";
        renderMessage("No pudimos abrir esta tienda", detail, true);
      } finally {
        loading = false;
      }
    };

    const cartTotal = () => (store?.products || []).reduce((sum, product) =>
      sum + Number(product.price || 0) * (cart.get(String(product.id)) || 0), 0);

    const renderCatalog = () => {
      if (!store) return;
      document.title = `${store.name} · Tienda Fideli`;
      root.replaceChildren();
      const shell = node("div", null, "storefront-shell");
      const header = node("header", null, "storefront-header");
      if (/^https:\/\//i.test(store.logo_url || '')) {
        const logo = document.createElement('img'); logo.src = store.logo_url;
        logo.alt = `Icono de ${store.name}`; logo.className = 'storefront-logo';
        logo.addEventListener('error', () => logo.remove(), {once: true}); header.append(logo);
      } else header.append(node('div', store.name.slice(0, 1), 'storefront-logo storefront-monogram'));
      const cartButton = node('button', `Carrito · ${[...cart.values()].reduce((a,b)=>a+b,0)}`, 'storefront-cart-button');
      cartButton.type = 'button'; cartButton.disabled = cart.size === 0;
      cartButton.addEventListener('click', openCheckout); header.append(cartButton);
      shell.append(header);
      shell.append(node("h1", store.name, "storefront-local"));
      shell.append(node("p", "Elige tus productos y confirma tu pedido.", "storefront-intro"));
      const categories = ["Todos", ...new Set(store.products.map((product) =>
        String(product.category || "General").trim() || "General"))];
      const categoryBar = node("nav", null, "storefront-categories");
      categoryBar.setAttribute("aria-label", "Categorías de productos");
      for (const category of categories) {
        const chip = node("button", category, `storefront-category${selectedCategory === category ? " is-selected" : ""}`);
        chip.type = "button";
        chip.setAttribute("aria-pressed", String(selectedCategory === category));
        chip.addEventListener("click", () => { selectedCategory = category; renderCatalog(); });
        categoryBar.append(chip);
      }
      shell.append(categoryBar);
      const list = node("section", null, "storefront-list");
      if (!store.products.length) list.append(node("p", "Este local todavía no publicó productos."));
      const visibleProducts = store.products.filter((product) => selectedCategory === "Todos" ||
        (String(product.category || "General").trim() || "General") === selectedCategory);
      for (const product of visibleProducts) {
        const id = String(product.id);
        const row = node("article", null, "storefront-product");
        const imageUrl = String(product.image_url || "").trim();
        if (/^https?:\/\//i.test(imageUrl)) {
          const image = document.createElement("img");
          image.className = "storefront-product-image";
          image.src = imageUrl;
          image.alt = product.name;
          image.loading = "lazy";
          image.referrerPolicy = "no-referrer";
          image.addEventListener("error", () => image.remove(), { once: true });
          image.tabIndex = 0;
          image.setAttribute("role", "button");
          image.setAttribute("aria-label", `Ver detalles de ${product.name}`);
          image.addEventListener("click", () => openProduct(product));
          image.addEventListener("keydown", (event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              openProduct(product);
            }
          });
          row.append(image);
        } else {
          row.append(node("div", "F", "storefront-product-image storefront-product-placeholder"));
        }
        const info = node("div");
        info.className = "storefront-product-info";
        info.append(node("small", String(product.category || "General"), "storefront-product-category"));
        const detailButton = node('button', product.name, 'storefront-product-title');
        detailButton.type = 'button';
        detailButton.addEventListener('click', () => openProduct(product));
        info.append(detailButton);
        if (product.description) info.append(node("p", product.description));
        info.append(node("div", money(product.price), "storefront-price"));
        const controls = node("div", null, "storefront-controls");
        const count = node("span", cart.get(id) || 0, "storefront-count");
        count.setAttribute("aria-live", "polite");
        const decrement = node("button", "−");
        decrement.type = "button";
        decrement.setAttribute("aria-label", `Quitar ${product.name}`);
        decrement.disabled = !(cart.get(id) > 0);
        decrement.addEventListener("click", () => {
          const next = Math.max(0, (cart.get(id) || 0) - 1);
          next ? cart.set(id, next) : cart.delete(id);
          renderCatalog();
        });
        const increment = node("button", "+");
        increment.type = "button";
        increment.setAttribute("aria-label", `Agregar ${product.name}`);
        increment.disabled = (cart.get(id) || 0) >= 99;
        increment.addEventListener("click", () => {
          cart.set(id, Math.min(99, (cart.get(id) || 0) + 1));
          renderCatalog();
        });
        if (cart.get(id) > 0) controls.append(decrement, count, increment);
        else {
          const add = node("button", "＋ Agregar", "storefront-add");
          add.type = "button";
          add.setAttribute("aria-label", `Agregar ${product.name}`);
          add.addEventListener("click", () => { cart.set(id, 1); renderCatalog(); });
          controls.append(add);
        }
        row.append(info, controls);
        list.append(row);
      }
      shell.append(list);
      root.append(shell);

      const checkout = node("div", null, "storefront-checkout");
      const inner = node("div", null, "storefront-checkout-inner");
      const total = node("div", null, "storefront-total");
      total.append(node("small", "Total aproximado"), node("strong", money(cartTotal())));
      const button = node("button", "Continuar", "storefront-action");
      button.type = "button";
      button.disabled = cartTotal() <= 0 || sending;
      button.addEventListener("click", openCheckout);
      inner.append(total, button);
      checkout.append(inner);
      root.append(checkout);
    };

    const openProduct = (product) => {
      const dialog = document.createElement('dialog');
      dialog.className = 'storefront-dialog storefront-product-dialog';
      dialog.setAttribute('aria-labelledby', 'storefront-detail-title');
      const content = node('div', null, 'storefront-detail');
      const top = node('div', null, 'storefront-detail-top');
      const category = String(product.category || 'General').trim() || 'General';
      top.append(node('small', category, 'storefront-product-category'));
      const close = node('button', '×', 'storefront-detail-close');
      close.type = 'button';
      close.setAttribute('aria-label', 'Cerrar detalles del producto');
      close.addEventListener('click', () => dialog.close());
      top.append(close);
      content.append(top);
      if (/^https?:\/\//i.test(product.image_url || '')) {
        const photo = document.createElement('img');
        photo.src = product.image_url;
        photo.alt = product.name;
        photo.className = 'storefront-detail-image';
        photo.referrerPolicy = 'no-referrer';
        content.append(photo);
      }
      const title = node('h2', product.name);
      title.id = 'storefront-detail-title';
      content.append(title);
      content.append(node('strong', money(product.price), 'storefront-detail-price'));
      content.append(node('p', product.description || 'Consulta al local si necesitas más información.', 'storefront-detail-description'));
      const actions = node('div', null, 'storefront-dialog-actions');
      const add = node('button', 'Agregar al carrito', 'storefront-action'); add.type = 'button';
      add.onclick = () => { const id = String(product.id); cart.set(id, Math.min(99, (cart.get(id) || 0) + 1)); dialog.close(); renderCatalog(); };
      actions.append(add);
      content.append(actions);
      dialog.append(content);
      root.append(dialog);
      dialog.addEventListener('click', (event) => {
        if (event.target === dialog) dialog.close();
      });
      dialog.addEventListener('close', () => dialog.remove(), { once: true });
      dialog.showModal();
      close.focus({ preventScroll: true });
    };

    const openCheckout = () => {
      const dialog = document.createElement("dialog");
      dialog.className = "storefront-dialog";
      const form = document.createElement("form");
      form.method = "dialog";
      form.append(node("h2", "Tus datos"), node("p", `Pedido para ${store.name}.`));
      const nameLabel = node("label", "Nombre");
      const name = document.createElement("input");
      name.name = "customer-name";
      name.autocomplete = "name";
      name.required = true;
      name.minLength = 2;
      name.maxLength = 120;
      nameLabel.append(name);
      const phoneLabel = node("label", "Teléfono (opcional)");
      const phone = document.createElement("input");
      phone.name = "customer-phone";
      phone.autocomplete = "tel";
      phone.type = "tel";
      phone.maxLength = 40;
      phoneLabel.append(phone);
      const commentLabel = node("label", "Comentarios (opcional)");
      const comment = document.createElement("textarea");
      comment.maxLength = 1000; comment.rows = 3;
      commentLabel.append(comment);
      const error = node("p", "", "storefront-error");
      const actions = node("div", null, "storefront-dialog-actions");
      const cancel = node("button", "Volver", "storefront-link secondary");
      cancel.type = "button";
      cancel.addEventListener("click", () => dialog.close());
      const submit = node("button", "Confirmar", "storefront-action");
      submit.type = "submit";
      actions.append(cancel, submit);
      const summary = node('section', null, 'storefront-order-summary');
      for (const product of store.products) {
        const quantity = cart.get(String(product.id));
        if (quantity) summary.append(node('p', `${quantity} × ${product.name} · ${money(quantity * Number(product.price))}`));
      }
      summary.append(node('strong', `Total aproximado: ${money(cartTotal())}`));
      form.append(summary, nameLabel, phoneLabel, commentLabel, error, actions);
      dialog.append(form);
      root.append(dialog);
      dialog.addEventListener("close", () => dialog.remove());
      dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (sending) return;
        sending = true;
        submit.disabled = true;
        submit.textContent = "Registrando…";
        error.textContent = "";
        try {
          const client = window.supabase.createClient(config.url, config.key, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
          });
          const items = [...cart.entries()].map(([id, quantity]) => ({ id, quantity }));
          const payload = {
            p_slug: slug,
            p_name: name.value.trim(),
            p_phone: phone.value.trim(),
            p_comment: comment.value.trim(),
            p_items: items,
          };
          const { data, error: rpcError } = await client.rpc('place_storefront_order', {
            ...payload, p_request_id: requestFor(payload),
          });
          if (rpcError) throw rpcError;
          if (!data?.id || !Array.isArray(data.items) || !Number.isFinite(Number(data.total))) {
            throw new Error("El local registró el pedido, pero no pudimos verificar su código. Contacta al local antes de volver a enviarlo.");
          }
          const digits = String(data.whatsapp_phone || "").replace(/\D/g, "");

          const lines = data.items.map((item) => `${item.quantity} × ${item.name} — ${money(item.line_total)}`).join("\n");
          const message = `Pedido ${data.id} · ${data.business_name}\n${lines}\nTotal verificado: ${money(data.total)}\nCliente: ${name.value.trim()}${phone.value.trim() ? `\nTeléfono: ${phone.value.trim()}` : ""}${data.customer_comment ? `\nComentarios: ${data.customer_comment}` : ""}`;
          const whatsappUrl = new URL(`https://wa.me/${digits}`);
          whatsappUrl.searchParams.set("text", message);
          dialog.close();
          sessionSave(receiptKey, data);
          sessionRemove(checkoutKey);
          lastRequest = null;
          renderSuccess(data);
          // Open only the final URL: never leave a preopened blank tab behind.
          // Failure to launch WhatsApp never invalidates a saved order.
          if (digits.length >= 8) {
            try { window.open(whatsappUrl.toString(), '_blank', 'noopener,noreferrer'); } catch (_) {}
          }
        } catch (submitError) {

          error.textContent = safeOrderError(submitError);
          sending = false;
          submit.disabled = false;
          submit.textContent = "Confirmar";
        }
      });
      dialog.showModal();
      name.focus();
    };

    const renderSuccess = (order) => {
      root.replaceChildren();
      const receipt = node('section', null, 'storefront-receipt');
      receipt.append(node('div', '✓', 'storefront-receipt-check'),
        node('p', 'Pedido registrado', 'storefront-receipt-status'),
        node('h1', order.business_name), node('h2', 'Comprobante de pedido'),
        node('p', `Código ${order.id}`, 'storefront-receipt-code'));
      if (order.created_at) receipt.append(node('p', new Date(order.created_at).toLocaleString('es-BO'), 'storefront-receipt-date'));
      if (order.customer_name) receipt.append(node('p', `Cliente: ${order.customer_name}`));
      if (order.customer_comment) receipt.append(node('p', `Comentarios: ${order.customer_comment}`));
      if (order.customer_phone) receipt.append(node('p', `Teléfono: ${order.customer_phone}`));
      const items = node('div', null, 'storefront-receipt-items');
      for (const item of order.items) {
        const row = node('div', null, 'storefront-receipt-row');
        const detail = node('div');
        detail.append(node('strong', `${item.quantity} × ${item.name}`), node('small', `${money(item.price)} por unidad`));
        row.append(detail, node('strong', money(item.line_total))); items.append(row);
      }
      const total = node('div', null, 'storefront-receipt-row storefront-receipt-total');
      total.append(node('strong', 'Total'), node('strong', money(order.total)));
      receipt.append(items, total);
      const back = node('button', 'Ver catálogo', 'storefront-action'); back.type = 'button';
      back.addEventListener('click', () => {
        sessionRemove(receiptKey); cart.clear(); sending = false; renderCatalog();
      });
      receipt.append(back); root.append(receipt);
      window.scrollTo({top: 0, behavior: 'instant'});
    };

    await load();
  };
})();
