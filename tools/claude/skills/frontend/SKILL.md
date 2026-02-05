---
name: frontend
description: Frontend development patterns for React, Tailwind, and modern web apps. Use for UI components, styling, accessibility, and state management.
---

# Frontend Development

## Component Structure

```
src/
├── components/     # reusable UI
│   ├── ui/         # primitives (button, input)
│   └── features/   # domain-specific
├── hooks/          # custom hooks
├── lib/            # utilities
└── app/            # routes/pages
```

## React Patterns

### Components

```tsx
interface Props {
  title: string;
  onClick?: () => void;
}

export function Card({ title, onClick }: Props) {
  return (
    <div className="p-4 rounded-lg border" onClick={onClick}>
      {title}
    </div>
  );
}
```

### Conditional Rendering

```tsx
// prefer early return
if (loading) return <Spinner />;
if (error) return <Error message={error} />;
return <Content data={data} />;
```

## Tailwind

### Spacing

`p-1` = 4px, `p-2` = 8px, `p-4` = 16px, `p-6` = 24px

### Responsive

```tsx
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
```

### Dark Mode

```tsx
<div className="bg-white dark:bg-gray-900">
```

### Common Patterns

```tsx
// card
"rounded-lg border bg-card p-6 shadow-sm"

// button
"inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium"

// center
"flex items-center justify-center"
```

## Accessibility

### Required

- images need `alt`
- buttons need text or `aria-label`
- forms need `<label>`
- contrast ≥ 4.5:1

### Keyboard

- interactive elements focusable
- `focus:ring-2` for focus ring
- escape closes modals

### Semantic HTML

```tsx
<button> not <div onClick>
<a href> for navigation
<nav>, <main>, <header>, <footer>
```

## State Management

### Local

```tsx
const [count, setCount] = useState(0);
```

### Zustand (shared)

```tsx
const useStore = create<Store>((set) => ({
  count: 0,
  inc: () => set((s) => ({ count: s.count + 1 })),
}));
```

### TanStack Query (server)

```tsx
const { data, isLoading } = useQuery({
  queryKey: ["users"],
  queryFn: () => fetch("/api/users").then((r) => r.json()),
});
```

## Forms (react-hook-form + zod)

```tsx
const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

const { register, handleSubmit } = useForm({
  resolver: zodResolver(schema),
});
```

## shadcn/ui

Use the shadcn MCP tools to browse and install components:

- `mcp__shadcn__search_items_in_registries` - find components
- `mcp__shadcn__view_items_in_registries` - see component code
- `mcp__shadcn__get_add_command_for_items` - get install command

Components install to `src/components/ui/`. Customize in place.

## Performance

- `React.lazy()` + `Suspense` for routes
- `useMemo`, `useCallback` for expensive ops
- `@tanstack/react-virtual` for long lists
- next/image for optimized images
