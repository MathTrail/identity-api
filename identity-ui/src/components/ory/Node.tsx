import { UiNode, UiNodeAnchorAttributes, UiNodeInputAttributes, UiNodeTextAttributes } from '@ory/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

interface NodeProps {
  node: UiNode
  disabled?: boolean
}

export function Node({ node, disabled }: NodeProps) {
  const attrs = node.attributes

  if (attrs.node_type === 'input') {
    const input = attrs as UiNodeInputAttributes

    if (input.type === 'submit') {
      return (
        <Button
          type="submit"
          name={input.name}
          value={input.value as string}
          disabled={disabled}
          className="w-full"
        >
          {node.meta.label?.text ?? 'Submit'}
        </Button>
      )
    }

    if (input.type === 'hidden') {
      return <input type="hidden" name={input.name} value={input.value as string} />
    }

    return (
      <div className="space-y-2">
        {node.meta.label && (
          <Label htmlFor={input.name}>{node.meta.label.text}</Label>
        )}
        <Input
          id={input.name}
          name={input.name}
          type={input.type}
          defaultValue={input.value as string}
          disabled={input.disabled || disabled}
          required={input.required}
        />
        {node.messages?.map((msg) => (
          <p key={msg.id} className="text-sm text-destructive">
            {msg.text}
          </p>
        ))}
      </div>
    )
  }

  if (attrs.node_type === 'text') {
    const text = attrs as UiNodeTextAttributes
    return (
      <p className="text-sm text-muted-foreground">
        {text.text?.text ?? node.meta.label?.text}
      </p>
    )
  }

  if (attrs.node_type === 'a') {
    const anchor = attrs as UiNodeAnchorAttributes
    return (
      <a
        href={anchor.href}
        className="text-sm text-primary underline-offset-4 hover:underline"
      >
        {anchor.title?.text ?? node.meta.label?.text}
      </a>
    )
  }

  return null
}
